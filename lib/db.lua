local semver = require('creationix/semver')
local git = require('creationix/git')
local sshRsa = require('creationix/ssh-rsa')

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
return function (storage, upstream)

  local db = {}

  --[[
  db.match(name, version) -> version, hash
  ----------------------------------------

  Given a semver version (or nil for any) return the best available version with
  hash (or nil if no match).

  If online, combine remote versions list.
  ]]--
  function db.match(name, version)
    version = semver.match(version, storage.versions(name))
    if upstream then
      version = semver.max(version, semver.match(version, upstream.versions(name)))
    end
    if not version then return end
    local hash = storage.read(formatTag(name, version))
    if not hash then return end
    return version, hash
  end

  --[[
  db.loadAs(kind, hash) -> value
  -----------------------------------

  Given a git kind and hash, return the pre-parsed value.  Verifies the kind is
  the kind expected.

  If missing locally and online, load from upstream and cache locally before
  returning.

  If it's a tag or a tree when caching locally, pre-fetch all child objects till
  the object's entire sub-graph is cached locally.

  If it's a tag, verify the signature before continuing.
  ]]--
  function db.loadAs(kind, hash)
    local data, err = storage.load(hash)
    assert(not err, err)
    if data then
      local actualKind
      data, actualKind = git.deframe(data)
      assert(kind == actualKind, "kind mistmatch")
      return git.decoders[kind](data)
    end
    if kind == "tag" then
      data, err = upstream.fetch(storage, hash)
      assert(not err, err)
      return data
    end
  end

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
    return storage.save(value)
  end

  --[[
  db.tag(config, hash, kind, tag, message) -> hash
  ------------------------------------------------

  If the tag with version already exists, it will error.

  Create an annotated tag for a package, sign using the config data and save to
  storage returning the hash.
  ]]--
  function db.tag(config, hash, kind, name, version, message)
    assert(config.key, "need ssh key to sign tag")
    version = semver.normalize(version)
    local tag = formatTag(name, version)
    assert(not storage.read(tag), "tag already exists")
    if string.sub(message, #message) ~= "\n" then
      message = message .. "\n"
    end

    return db.saveAs("tag", sshRsa.sign(git.encoders.tag({
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
  end

  --[[
  db.push(tag, version)
  ---------------------

  Given a tag and concrete version, push to upstream.  Can only be done for tags
  the user has personally signed.  Will conflict if upstream has tag already
  ]]--
  function db.push(config, name, version)
    assert(upstream, "upstream required to push")
    version = semver.normalize(version)
    local tag = formatTag(name, version)
    local prefix = config.username .. "/"
    assert(prefix == string.sub(tag, 1, #prefix), "not own package")
    assert(not upstream.read(tag), "tag conflict in upstream")
    local hash = assert(storage.read(tag), "no such local tag")
    upstream.send(storage, hash)
  end

end
