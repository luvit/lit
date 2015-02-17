--[[

Core Functions
==============

These are the high-level actions.  This consumes a database instance

core.add(path) -> author, name, version, hash - Import a package complete with signed tag.
]]

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


return function (db, config, getKey)

  local jsonStringify = require('json').stringify
  local log = require('./log')
  local githubQuery = require('./github-request')
  local pkg = require('./pkg')
  local sshRsa = require('ssh-rsa')
  local git = require('git')
  local encoders = git.encoders
  local semver = require('semver')
  local normalize = semver.normalize
  local pathJoin = require('luvi').path.join

  local core = {}

  core.config = config
  core.db = db
  if config.upstream then
    db = require('./rdb')(db, config.upstream)
  end

  function core.add(path)
    local author, name, version = pkg.normalize(pkg.query(path))
    local kind, hash = db.import(path)
    local oldTagHash = db.read(author, name, version)
    local fullTag = author .. "/" .. name .. '/v' .. version
    if oldTagHash then
      local old = db.loadAs("tag", oldTagHash)
      if old.type == kind and old.object == hash then
        -- This package is already imported and tagged
        log("no change", fullTag)
        return author, name, version, oldTagHash
      end
      log("replacing tag with new contents", fullTag, "failure")
    end
    local encoded = encoders.tag({
      object = hash,
      type = kind,
      tag = author .. '/' .. name .. "/v" .. version,
      tagger = {
        name = config.name,
        email = config.email,
        date = now()
      },
      message = ""
    })
    local key = getKey()
    if key then
      encoded = sshRsa.sign(encoded, key)
    end
    local tagHash = db.saveAs("tag", encoded)
    db.write(author, name, version, tagHash)
    log("new tag", fullTag, "success")
    return author, name, version, tagHash
  end

  function core.publish(path)
    if not config.upstream then
      error("Must be configured with upstream to publish")
    end
    local author, name= core.add(path)
    local tag = author .. '/' .. name

    -- Loop through all local versions that aren't upstream
    local queue = {}
    for version in db.versions(author, name) do
      if not db.readRemote(author, name, version) then
        local hash = db.read(author, name, version)
        queue[#queue + 1] = {tag, version, hash}
      end
    end

    if #queue == 0 then
      log("nothing to publish", tag)
      return
    end

    for i = 1, #queue do
      local tag, version, hash = unpack(queue[i])
      log("publishing", tag .. '@' .. version)
      db.push(hash)
    end

  end

  function core.importKeys(username)

    local path = "/users/" .. username .. "/keys"
    local etag = db.getEtag(username)
    local head, keys, url = githubQuery(path, etag)

    if head.code == 304 then return url end
    if head.code == 404 then
      error("No such username at github: " .. username)
    end

    if head.code ~= 200 then
      p(head)
      error("Invalid http response from github API: " .. head.code)
    end

    local fingerprints = {}
    for i = 1, #keys do
      local sshKey = sshRsa.loadPublic(keys[i].key)
      if sshKey then
        local fingerprint = sshRsa.fingerprint(sshKey)
        fingerprints[fingerprint] = sshKey
      end
    end

    local iter = db.fingerprints(username)
    if iter then
      for fingerprint in iter do
        if fingerprints[fingerprint] then
          fingerprints[fingerprint]= nil
        else
          log("revoking key", username .. ' ' .. fingerprint, "error")
          db.revokeKey(username, fingerprint)
        end
      end
    end

    for fingerprint, sshKey in pairs(fingerprints) do
      db.putKey(username, fingerprint, sshRsa.writePublic(sshKey))
      log("imported key", username .. ' ' .. fingerprint, "highlight")
    end

    for i = 1, #head do
      local name, value = unpack(head[i])
      if name:lower() == "etag" then etag = value end
    end
    db.setEtag(username, etag)

    return url
  end

  function core.authUser()
    local key = assert(getKey(), "No private key")
    local rsa = key:parse().rsa:parse()
    local sshKey = sshRsa.encode(rsa.e, rsa.n)
    local fingerprint = sshRsa.fingerprint(sshKey)
    log("checking ssh fingerprint", fingerprint)
    local url = core.importKeys(config.username)

    if not db.readKey(config.username, fingerprint) then
      error("Private key doesn't match keys at " .. url)
    end
  end

  function core.addDep(deps, modulesDir, alias, author, name, version)

    -- Find best match in local and remote databases
    local match, hash = db.match(author, name, version)
    if not match then
      if version then
        error("No matching package: " .. author .. "/" .. name .. '@' .. version)
      else
        error("No such package: " .. author .. '/' .. name)
      end
    end
    version = match

    -- Check for conflicts with already added dependencies
    local existing = deps[alias]
    if existing then
      if existing.author == author and existing.name == name then
        -- If this exact version is already done, stop recursion here.
        if existing.version == version then return end

        -- Warn about incompatable versions being required
        local message = string.format("%s %s ~= %s",
          alias, existing.version, version)
        log("version mismatch", message, "failure")
        -- Use the newer version in case of mismatch
        if semver.gte(existing.version, version) then return end
      else
        -- Warn about alias name conflicts
        local message = string.format("%s %s/%s ~= %s/%s",
          alias, existing.author, existing.name, author, name)
        log("alias conflict", message, "failure")
        -- Use the first added in case of mismatch
        return
      end
    end

    -- Check for existing packages in the "modules" dir on disk
    if modulesDir then
      local meta, path = pkg.query(pathJoin(modulesDir, alias))
      if meta then
        if meta.name ~= author .. '/' .. name then
          local message = string.format("%s %s ~= %s/%s",
            alias, meta.name, author, name)
          log("alias conflict (disk)", message, "failure")
        elseif meta.version ~= version then
          local message = string.format("%s %s ~= %s",
            alias, meta.version, version)
          log("version mismatch (disk)", message, "highlight")
        end

        deps[alias] = {
          author = author,
          name = name,
          version = version,
          disk = path
        }

        if not meta.dependencies then return end
        return core.processDeps(deps, modulesDir, meta.dependencies)
      end
    end

    deps[alias] = {
      author = author,
      name = name,
      version = version,
      hash = hash
    }

    deps[#deps + 1] = hash
  end

  function core.processDeps(deps, modulesDir, list)
    for alias, dep in pairs(list) do
      if type(alias) == "number" then
        alias = string.match(dep, "/([^@]+)")
      end
      local author, name = string.match(dep, "^([^/@]+)/([^@]+)")
      local version = string.match(dep, "@(.+)")
      if version then version = normalize(version) end
      core.addDep(deps, modulesDir, alias, author, name, version)
    end
    local hashes = {}
    for i = 1, #deps do
      hashes[i] = deps[i]
      deps[i] = nil
    end
    if db.fetch then
      db.fetch(hashes)
    end
    for i = 1, #hashes do
      local meta = pkg.queryDb(db, hashes[i])
      if meta.dependencies then
        core.processDeps(deps, modulesDir, meta.dependencies)
      end
    end

  end

  local function install(modulesDir, deps)
    if db.fetch then
      local hashes = {}
      for _, dep in pairs(deps) do
        if dep.hash then
          hashes[#hashes + 1] = dep.hash
        end
      end
      db.fetch(hashes)
    end
    for alias, dep in pairs(deps) do
      if dep.hash then
        local tag = db.loadAs("tag", dep.hash)
        local target = pathJoin(modulesDir, alias) ..
          (tag.type == "blob" and ".lua" or "")
        local filename = "modules/" .. alias .. (tag.type == "blob" and ".lua" or "/")
        log("installing", string.format("%s/%s@%s -> %s",
          dep.author, dep.name, dep.version, filename), "highlight")
        db.export(tag.object, target)
      end
    end
  end


  function core.installList(path, list)
    local deps = {}
    core.processDeps(deps, nil, list)
    return install(pathJoin(path, "modules"), deps)
  end


  function core.installDeps(path)
    local meta = pkg.query(path)
    if not meta.dependencies then
      log("no dependencies", path)
      return
    end
    local deps = {}
    local modulesDir = pathJoin(path, "modules")
    core.processDeps(deps, modulesDir, meta.dependencies)
    return install(modulesDir, deps)
  end

  local function makeRequest(name, req)
    local key = getKey()
    if not (key and config.name and config.email) then
      error("Please run `lit auth` to configure your username")
    end
    assert(db.upquery, "upstream required to publish")
    req.username = config.username
    local json = jsonStringify(req) .. "\n"
    local signature = sshRsa.sign(json, key)
    return db.upquery(name, signature)
  end

  function core.claim(org)
    return makeRequest("claim", { org = org })
  end

  function core.share(org, friend)
    return makeRequest("share", { org = org, friend = friend })
  end

  function core.unclaim(org)
    return makeRequest("unclaim", { org = org })
  end

  return core
end
