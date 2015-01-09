local semver = require('creationix/semver')
local git = require('creationix/git')
local sshRsa = require('creationix/ssh-rsa')
local fs = require('creationix/coro-fs')
local readPackage = require('./read-package').read
local import = require('./import')
local export = require('./export')
local makeUpstream = require('./upstream')
local uv = require('uv')
local parseVersion = require('./parse-version')
local log = require('./log')

-- Takes a time struct with a date and time in UTC and converts it into
-- seconds since Unix epoch (0:00 1 Jan 1970 UTC).
-- Trickier than you'd think because os.time assumes the struct is in local time.
local function now()
  local t_secs = os.time() -- get seconds if t was in local time.
  local t = os.date("*t", t_secs) -- find out if daylight savings was applied.
  local t_UTC = os.date("!*t", t_secs) -- find out what UTC t was converted to.
  t_UTC.isdst = t.isdst -- apply DST to this time if necessary.
  local UTC_secs = os.time(t_UTC) -- find out the converted time in seconds.
  return {
    seconds = t_secs,
    offset = os.difftime(t_secs, UTC_secs) / 60
  }
end

--[[
DB Interface
============

Medium level interface over storage used to implement commands.

exports(storage, upstream) -> db
--------------------------------

Given two storage instances (one local, one remote if online), return a
db interface implementation.
]]--
return function (storage, host, port)

  local upstream
  local timer
  local function connect()
    if timer then
      timer:close()
      timer = nil
    end
    upstream = upstream or assert(makeUpstream(storage, host, port))
  end

  local function close()
    if timer then
      timer:close()
      timer = nil
    end
    if upstream then
      upstream.close()
      upstream = nil
    end
  end

  local function disconnect()
    if timer then
      timer:stop()
    else
      timer = uv.new_timer()
      timer:unref()
    end
    timer:start(100, 0, close)
  end

  local db = {}
  db.storage = storage

  --[[
  db.match(name, version) -> version, hash
  ----------------------------------------

  Given a semver version (or nil for any) return the best available version with
  hash (or nil if no match).

  If online, combine remote versions list.
  ]]--
  function db.match(name, version)
    local iter, err = storage.versions(name)
    if err then return nil, err end
    local match = iter and semver.match(version, iter)
    if host then
      -- If we're online, check the remote for a possibly better match.
      local upMatch, hash
      connect()
      upMatch, hash = upstream.match(name, version)
      disconnect()
      if not upMatch then return nil, hash end
      if not semver.gte(match, upMatch) then
        return upMatch, hash
      end
    end
    if not match then return end
    local hash = storage.readTag(name, match)
    if not hash then return end
    return match, hash
  end

  --[[
  db.read(name, version) -> hash

  Read hash directly without doing match. Checks upstream if not found locally.
  ]]--
  function db.read(name, version)
    assert(version, "version required for direct read")
    version = semver.normalize(version)
    local hash, err = storage.readTag(name, version)
    if not hash and host then
      connect()
      hash = upstream.read(name, version)
      disconnect()
    end
    if hash then
      return hash
    end
    return nil, err or "no such tag"
  end

  --[[
  db.loadAs(kind, hash) -> value
  -----------------------------------

  Given a git kind and hash, return the pre-parsed value.  Verifies the kind is
  the kind expected.

  If missing locally and there is an upstream, load from upstream and cache
  locally before returning.

  When fetching from upstream, pre-fetch all child objects till the object's
  entire sub-graph is cached locally.
  ]]--
  function db.loadAs(kind, hash)
    local data, err = db.load(hash)
    assert(not err, err)
    if not data then return nil, err end

    local actualKind
    actualKind, data = git.deframe(data)
    assert(kind == actualKind, "kind mistmatch")
    return git.decoders[kind](data)
  end

  db.load = function (hash)
    local data, err = storage.load(hash)
    if not data and host then
      connect()
      data, err = upstream.load(hash)
      disconnect()
      assert(storage.save(data) == hash)
    end
    return data, err
  end

  db.save = storage.save

  --[[
  db.saveAs(kind, value) -> hash
  ------------------------------

  Value can be an object to be encoded or a pre-encoded raw string.  It will
  auto-detect since blobs are the same either way.
  ]]--
  function db.saveAs(kind, value)
    if type(value) ~= "string" then
      value = git.encoders[kind](value)
    end
    value = git.frame(kind, value)
    return storage.save(value)
  end

  --[[
  db.tag(config, hash, message) -> name, version, hash
  ------------------------------------------------

  Create an annotated tag for a package, sign using the config data and save to
  storage returning the hash.

  The tag name and version are pulled from the data itself. If it's a blob, it's
  run as lua code in a sandbox and exports.name and exports.version are looked
  for. If it's a tree, the entry `package.lua` is looked for and same eval is
  done looking for name and version.

  If the tag with version already exists, it will error.
  ]]--
  function db.tag(config, hash, message)
    assert(config.key, "need ssh key to sign tag, setup with `lit auth`")
    assert(hash, "Hash required to tag")

    local kind, meta = readPackage(storage, hash)
    local version = semver.normalize(meta.version)
    local name = meta.name

    assert(not storage.readTag(name, version), "tag already exists")
    if string.sub(message, #message) ~= "\n" then
      message = message .. "\n"
    end

    hash = db.saveAs("tag", sshRsa.sign(git.encoders.tag({
      object = hash,
      type = kind,
      tag = name .. "/v" .. version,
      tagger = {
        name = config.name,
        email = config.email,
        date = now()
      },
      message = message
    }), config.key))
    storage.writeTag(name, version, hash)
    return name, version, hash
  end

  function db.pull(name, version)
    assert(host, "upstream required to pull")
    connect()
    local match, hash = assert(upstream.match(name, version))
    local success, err = upstream.pull(hash)
    disconnect()
    if success then
      return match, hash
    end
    return nil, err
  end

  --[[
  db.publish(name, version)
  ---------------------

  Given a package name, publish to upstream. Can only be done for tags the
  user has personally signed. Will conflict if upstream has tag already.
  ]]--
  function db.publish(name)
    assert(host, "upstream required to publish")

    -- Loop through all local versions that aren't upstream
    local queue = {}
    connect()
    for version in storage.versions(name) do
      if not upstream.read(name, version) then
        local hash = storage.readTag(name, version)
        queue[#queue + 1] = {name, version, hash}
      end
    end
    if #queue == 0 then
      print("Warning: All local versions are already published, maybe add a new local version?")
    end

    for i = 1, #queue do
      local name, version, hash = unpack(queue[i])
      log("publishing", name .. '@' .. version)
      local _, meta = readPackage(db, hash)
      -- Make sure all deps are satisifiable in upstream before publishing broken package there.
      local deps = meta.dependencies
      if deps then
        for i = 1, #deps do
          local name, version = parseVersion(deps[i])
          if not upstream.match(name, version) then
            error("Cannot find suitable dependency match in upstream for: " .. deps[i])
          end
        end
      end
      upstream.push(hash)
    end
    disconnect()
  end

  --[[
  db.import(path) -> hash
  -----------------------

  Import a file or tree from the filesystem and return the hash
  ]]--
  function db.import(path)
    local stat = fs.lstat(path)
    if stat.type == "file" then
      return import.blob(db, path)
    elseif stat.type == "directory" then
      return import.tree(db, path)
    else
      error("Unsupported type " .. stat.type)
    end
  end

  --[[
  db.export(path, hash)
  -----------------------

  Export a package to the filesystem.
  ]]--
  function db.export(path, hash)
    local tag = assert(db.loadAs("tag", hash))
    if tag.type == "blob" then
      path = path .. ".lua"
    end
    return export[tag.type](db, path, tag.object)
  end

  return db

end
