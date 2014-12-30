local semver = require('creationix/semver')
local git = require('creationix/git')
local sshRsa = require('creationix/ssh-rsa')
local fs = require('creationix/coro-fs')
local readPackage = require('./read-package').read
local import = require('./import')
local export = require('./export')
local makeUpstream = require('./upstream')
local uv = require('uv')

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

local function formatTag(name, version)
  return name .. '/v' .. version
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
    local hash = storage.read(formatTag(name, match))
    if not hash then return end
    return match, hash
  end

  --[[
  db.read(name, version) -> hash

  Read hash directly without doing match. Only reads local version.
  ]]--
  function db.read(name, version)
    assert(version, "version required for direct read")
    version = semver.normalize(version)
    local tag = formatTag(name, version)
    return storage.read(tag)
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
      data, err = upstream.read(hash)
      disconnect()
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
  db.tag(config, hash, message) -> tag, hash
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

    local kind, meta = readPackage(storage, hash)
    local version = semver.normalize(meta.version)
    local name = meta.name
    local tag = formatTag(name, version)

    assert(not storage.read(tag), "tag already exists")
    if string.sub(message, #message) ~= "\n" then
      message = message .. "\n"
    end

    hash = db.saveAs("tag", sshRsa.sign(git.encoders.tag({
      object = hash,
      type = kind,
      tag = tag,
      tagger = {
        name = config.name,
        email = config.email,
        date = now()
      },
      message = message
    }), config.key))
    storage.write(tag, hash)
    return tag, hash
  end

  function db.pull(name, version)
    assert(host, "upstream required to pull")
    local match, hash = assert(upstream.match(name, version))
    connect()
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

  Given a tag and concrete version, publish to upstream.Can only be done for
  tags the user has personally signed.Will conflict if upstream has tag already.
  ]]--
  function db.publish(name, version)
    assert(host, "upstream required to push")
    version = semver.normalize(version)
    connect()
    local hash, err = upstream.push(name, version)
    disconnect()
    return hash, err
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
