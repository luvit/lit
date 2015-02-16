local semver = require('semver')
local git = require('git')
local sshRsa = require('ssh-rsa')
local fs = require('coro-fs')
local readPackage = require('./read-package').read
local readPackageFs = require('./read-package').readFs
local import = require('./import')
local export = require('./export')
local makeUpstream = require('./upstream')
local uv = require('uv')
local parseVersion = require('./parse-version')
local log = require('./log')
local jsonStringify = require('json').stringify


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
  db.add(config, path) -> name, version, tagHash
  ------------------------------------------------

  Create an annotated tag for a package, sign using the config data and save to
  storage returning the hash.

  The tag name and version are pulled from the data itself. If it's a blob, it's
  run as lua code in a sandbox and exports.name and exports.version are looked
  for. If it's a tree, the entry `package.lua` is looked for and same eval is
  done looking for name and version.

  If the tag with version already exists, it will error return a soft error.
  ]]--
  function db.add(config, path)

    if not (config.key and config.name and config.email) then
      error("Please run `lit auth` to configure your username")
    end

    local meta = readPackageFs(path)
    local name = meta.name
    local version = semver.normalize(meta.version)
    local tagHash = storage.readTag(name, version)
    if tagHash then
      return name, version, tagHash
    end
    local hash, kind = assert(db.import(path))
    tagHash = db.saveAs("tag", sshRsa.sign(git.encoders.tag({
      object = hash,
      type = kind,
      tag = name .. "/v" .. version,
      tagger = {
        name = config.name,
        email = config.email,
        date = now()
      },
      message = "\n"
    }), config.key))
    storage.writeTag(name, version, tagHash)
    log("added package", name .. "@" .. version .. " " .. tagHash)
    return name, version, tagHash
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
  function db.publish(config, path)
    assert(host, "upstream required to publish")

    local name = db.add(config, path)


    local iter = storage.versions(name)
    if not iter then
      error("No such package: " .. name)
    end

    -- Loop through all local versions that aren't upstream
    local queue = {}
    connect()
    log("publishing", name)
    for version in iter do
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
      return import.blob(db, path), "blob"
    elseif stat.type == "directory" then
      return import.tree(db, path), "tree"
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

  local function makeRequest(config, name, req)
    if not (config.key and config.name and config.email) then
      error("Please run `lit auth` to configure your username")
    end
    assert(host, "upstream required to publish")
    req.username = config.username
    local json = jsonStringify(req) .. "\n"
    local signature = sshRsa.sign(json, config.key)
    connect()
    local success, err = upstream[name](signature)
    disconnect()
    return success, err
  end

  function db.claim(config, org)
    return makeRequest(config, "claim", { org = org })
  end

  function db.share(config, org, friend)
    return makeRequest(config, "share", { org = org, friend = friend })
  end

  function db.unclaim(config, org)
    return makeRequest(config, "unclaim", { org = org })
  end

  return db

end