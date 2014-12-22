local semver = require('creationix/semver')
local git = require('creationix/git')
local sshRsa = require('creationix/ssh-rsa')
local fs = require('creationix/coro-fs')
local readStorage = require('./read-package').readStorage
local fetch = require('./fetch')
local import = require('./import')
local export = require('./export')
local makeUpstream = require('./upstream')

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
  local function connect()
    upstream = upstream or makeUpstream(storage, host, port)
  end

  local function disconnect()
    if upstream then upstream.close() end
    upstream = nil
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
    local upMatch
    if host then
      connect()
      upMatch, err = upstream.query("MATCH", name, version)
      if err then return nil, err end
    end
    local s = storage
    -- If the upstream version is better, use it instead
    if not semver.gte(match, upMatch) then
      s = upstream
      match = upMatch
    end
    if not match then return end
    local hash = s.read(formatTag(name, match))
    if not hash then return end
    disconnect()
    return match, hash
  end

  --[[
  db.read(name, version) -> hash

  Read hash directly without doing match
  ]]--
  function db.read(name, version)
    assert(version, "version required for direct read")
    version = semver.normalize(version)
    local tag = formatTag(name, version)
    local hash, err = storage.read(tag)
    if err then return nil, err end
    if hash then return hash end
    if host then
      connect()
      p("remote read")
      hash, err = upstream.query("READ", name, version)
      disconnect()
      return hash, err
    end
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
    local data, err = storage.load(hash)
    assert(not err, err)
    if not data and host then
      connect()
      p("REMOTE LOAD", hash)
      data, err = fetch(storage, upstream, hash)
      disconnect()
    end
    if not data then return nil, err end

    local actualKind
    actualKind, data = git.deframe(data)
    assert(kind == actualKind, "kind mistmatch")
    return git.decoders[kind](data)
  end

  db.load = storage.load

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

    local kind, meta = readStorage(storage, hash)
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


  --[[
  db.push(tag, version)
  ---------------------

  Given a tag and concrete version, push to upstream.  Can only be done for tags
  the user has personally signed.  Will conflict if upstream has tag already
  ]]--
  function db.push(name, version)
    assert(host, "upstream required to push")
    connect()
    version = semver.normalize(version)
    local tag = formatTag(name, version)
    local hash, success, err
    hash, err = storage.read(tag)
    if not hash then return nil, err or "No such tag to push" end
    success, err = upstream.query("PUSH", hash)
    disconnect()
    return success, err
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
  db.export(path, name, version)
  -----------------------

  Export a package to the filesystem.
  ]]--
  function db.export(path, name, version)
    local hash = assert(db.read(name, version))
    local tag = assert(db.loadAs("tag", hash))
    if tag.type == "blob" then
      path = path .. ".lua"
    end
    return export[tag.type](db, path, tag.object)
  end

  return db

end
