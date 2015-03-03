--[[

Core Functions
==============

These are the high-level actions.  This consumes a database instance

core.add(path) -> author, name, version, hash - Import a package complete with signed tag.
]]

local uv = require('uv')
local jsonStringify = require('json').stringify
local log = require('./log')
local githubQuery = require('./github-request')
local pkg = require('./pkg')
local sshRsa = require('ssh-rsa')
local git = require('git')
local modes = git.modes
local encoders = git.encoders
local semver = require('semver')
local normalize = semver.normalize
local pathJoin = require('luvi').path.join
local miniz = require('miniz')
local vfs = require('./vfs')
local fs = require('coro-fs')
local http = require('coro-http')
local prompt = require('prompt')(require('pretty-print'))

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

local function confirm(message)
  local res = prompt(message .. " (y/n)")
  return res and res:find("y")
end

return function (db, config, getKey)

  local core = {}

  core.config = config
  core.db = db
  if config.upstream then
    db = require('./rdb')(db, config.upstream)
  end

  function core.add(path)
    local fs
    fs, path = vfs(path)
    local meta = pkg.query(fs, path)
    if not meta then
      error("Not a package: " .. path)
    end
    local author, name, version = pkg.normalize(meta)
    if config.upstream then core.sync(author, name) end

    local kind, hash = db.import(fs, path)
    local oldTagHash = db.read(author, name, version)
    local fullTag = author .. "/" .. name .. '/v' .. version
    if oldTagHash then
      local old = db.loadAs("tag", oldTagHash)
      if old.type == kind and old.object == hash then
        -- This package is already imported and tagged
        log("no change", fullTag)
        return author, name, version, oldTagHash
      end
      error("Tag already exists, but there are local changes.\nBump " .. fullTag .. " and try again.")
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
    local author, name = core.add(path)
    local tag = author .. '/' .. name

    -- Loop through all local versions that aren't upstream
    local queue = {}
    for version in db.versions(author, name) do
      local hash = db.read(author, name, version)
      local match = db.match(author, name, version)
      local tag = db.loadAs("tag", hash)
      local meta = pkg.queryDb(db, tag.object)
      -- Skip private modules, obsolete modules, and non-signed modules
      local skip = false
      if match ~= version then
        skip = "Obsoleted version"
      elseif not meta then
        skip = "Old style metadata"
      elseif meta.private then
        skip = "Marked private"
      elseif not tag.message:find("-----BEGIN RSA SIGNATURE-----") then
        skip = "Package not signed"
      elseif db.readRemote(author, name, version) then
        skip = "Exists at upstream"
      end
      if skip then
        log("skipping", author .. "/" .. name .. "@" .. version .. ": " .. skip)
      else
        local tag = string.format("%s/%s/v%s", author, name, version)
        queue[#queue + 1] = {tag, version, hash}
      end
    end

    if #queue == 0 then
      log("nothing to publish", tag)
      return
    end

    for i = 1, #queue do
      local tag, version, hash = unpack(queue[i])
      if #queue == 1 or confirm(tag .. " -> " .. config.upstream .. "\nDo you wish to publish?") then
        log("publishing", tag .. '@' .. version, "highlight")
        db.push(hash)
      end
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

  local hashToDep = {}

  local function addDep(deps, fs, modulesDir, alias, author, name, version)
    -- Check for existing packages in the "deps" dir on disk
    if modulesDir then
      local meta, path = pkg.query(fs, pathJoin(modulesDir, alias))
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
          version = meta.version,
          disk = path
        }

        if not meta.dependencies then return end
        return core.processDeps(deps, fs, modulesDir, meta.dependencies)
      end
    end

    -- Find best match in local and remote databases
    local match, hash = db.match(author, name, version)
    if match then
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
    end

    if not match then
      if version then
        error("No such version: " .. author .. "/" .. name .. '@' .. version)
      else
        error("No such package: " .. author .. '/' .. name)
      end
    end

    deps[alias] = {
      author = author,
      name = name,
      version = version,
      hash = hash
    }
    hashToDep[hash] = alias

    deps[#deps + 1] = hash
  end

  function core.processDeps(deps, fs, modulesDir, list)

    for alias, dep in pairs(list) do
      if type(alias) == "number" then
        alias = string.match(dep, "/([^@]+)")
      end
      local author, name = string.match(dep, "^([^/@]+)/([^@]+)")
      local version = string.match(dep, "@(.+)")
      if not author then
        error("Package names must include owner/name at a minimum")
      end
      if version then version = normalize(version) end
      addDep(deps, fs, modulesDir, alias, author, name, version)
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
      if meta then
        if meta.dependencies then
          core.processDeps(deps, fs, modulesDir, meta.dependencies)
        end
      else
        local hash = hashes[i]
        local alias = hashToDep[hash] or "unknown"
        log("warning", "Can't find metadata in package: " .. alias .. "-" .. hash)
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
        local filename = "deps/" .. alias .. (tag.type == "blob" and ".lua" or "/")
        log("installing", string.format("%s/%s@%s -> %s",
          dep.author, dep.name, dep.version, filename), "highlight")
        db.export(tag.object, target)
      end
    end
  end

  function core.installList(path, list)
    local deps = {}
    core.processDeps(deps, fs, nil, list)
    return install(pathJoin(path, "deps"), deps)
  end


  function core.installDeps(path)
    local fs
    fs, path = vfs(path)
    local meta = pkg.query(fs, path)
    if not meta.dependencies then
      log("no dependencies", path)
      return
    end
    local deps = {}
    local modulesDir = pathJoin(path, "deps")
    core.processDeps(deps, fs, modulesDir, meta.dependencies)
    return install(modulesDir, deps)
  end

  local function importBlob(writer, path, hash)
    local data = db.loadAs("blob", hash)
    writer:add(path, data, 9)
  end

  local function importTree(writer, path, hash)
    local tree = db.loadAs("tree", hash)
    if path then
      writer:add(path .. "/", "")
    end
    for i = 1, #tree do
      local entry = tree[i]
      local newPath = path and path .. '/' .. entry.name or entry.name
      if entry.mode == modes.tree then
        importTree(writer, newPath, entry.hash)
      else
        importBlob(writer, newPath, entry.hash)
      end
    end
  end

  local function importPath(writer, fs, root, path, rules)
    local kind, hash = db.import(fs, pathJoin(root, path), rules)
    if kind == "tree" then
      importTree(writer, path, hash)
    else
      importBlob(writer, path, hash)
    end
  end

  function core.make(path, target)
    local fs
    fs, path = vfs(path)
    local meta = pkg.query(fs, path)
    if not target then
      target = meta.target or meta.name:match("[^/]+$")
      if require('ffi').os == "Windows" then
        target = target .. ".exe"
      end
    end
    log("creating binary", target, "highlight")

    local tempFile = target:gsub("[^/]+$", ".%1.temp")
    local fd = assert(uv.fs_open(tempFile, "w", 511)) -- 0777

    -- Copy base binary
    local binSize
    do
      local source = uv.exepath()

      local reader = miniz.new_reader(source)
      if reader then
        -- If contains a zip, find where the zip starts
        binSize = reader:get_offset()
      else
        -- Otherwise just read the file size
        binSize = uv.fs_stat(source).size
      end
      local fd2 = assert(uv.fs_open(source, "r", 384)) -- 0600
      log("copying binary prefix", binSize .. " bytes from " .. source)
      assert(uv.fs_sendfile(fd, fd2, 0, binSize))
      uv.fs_close(fd2)
    end

    local writer = miniz.new_writer()

    log("importing", #path > 0 and path or fs.base, "highlight")
    -- TODO: Find target relative to path and use that instead of just target
    importPath(writer, fs, path, nil, { "!" .. target })

    if meta.dependencies then
      local deps = {}
      local modulesDir = pathJoin(path, "deps")
      writer:add("deps/", "")
      core.processDeps(deps, fs, modulesDir, meta.dependencies)
      for alias, dep in pairs(deps) do
        local tag = dep.author .. '/' .. dep.name .. '@' .. dep.version
        if dep.disk then
          local name = "deps/" .. (dep.disk:match("([^/\\]+)$") or alias)
          log("adding", tag .. ' (' .. dep.disk .. ')', "highlight")
          importPath(writer, fs, path, name)
        elseif dep.hash then
          log("adding", tag, "highlight")
          local tag = db.loadAs("tag", dep.hash)
          if tag.type == "tree" then
            importTree(writer, "deps/" .. alias, tag.object)
          elseif tag.type == "blob" then
            importBlob(writer, "deps/" .. alias .. ".lua", tag.object)
          end
        end
      end
    end

    assert(uv.fs_write(fd, writer:finalize(), binSize))
    uv.fs_close(fd)
    assert(uv.fs_rename(tempFile, target))
    log("done building", target)

  end

  local aliases = {
    "^github://([^/]+)/([^/@]+)/?@(.+)$", "https://github.com/%1/%2/archive/%3.zip",
    "^github://([^/]+)/([^/]+)/?$", "https://github.com/%1/%2/archive/master.zip",
    "^gist://([^/]+)/(.+)/?$", "https://gist.github.com/%1/%2/download",
  }
  core.urlAilases = aliases

  local function makeHttp(target, url)
    local res, body = http.request("GET", url)
    assert(res.code == 200, body)
    local filename
    for i = 1, #res do
      local key, value = unpack(res[i])
      if key:lower() == "content-disposition" then
        filename = value:match("filename=([^;]+)")
      end
    end

    local path = filename or (target or "app") .. ".zip"
    fs.writeFile(path, body)
    core.make(path, target)
    fs.unlink(path)
  end

  local function makeGit(target, hostname, port, path)
    if path == "" then path = "/" end
    port = port and tonumber(port) or 9418
    p("TODO: git", {
      hostname = hostname,
      port = port,
      path = path
    })
  end

  local function makeLit(target, author, name, version)
    version = semver.normalize(version)
    p("LIT", {
      author = author,
      name = name,
      version = version
    })
  end

  local handlers = {
    "^(https?://[^#]+)$", makeHttp,
    "^git://([^/:]+):?([0-9]*)(/?.*)$", makeGit,
    "^lit://([^/]+)/([^@]+)@v?(.+)$", makeLit,
    "^lit://([^/]+)/([^@]+)$", makeLit,
    "^([^/]+)/([^@]+)@v?(.+)$", makeLit,
    "^([^/]+)/([^@]+)$", makeLit,
  }
  core.urlHandlers = handlers

  function core.makeUrl(url, target)
    local fullUrl = url
    for i = 1, #aliases, 2 do
      fullUrl = fullUrl:gsub(aliases[i], aliases[i + 1])
    end
    for i = 1, #handlers, 2 do
      local match = {fullUrl:match(handlers[i])}
      if #match > 0 then return handlers[i + 1](target, unpack(match)) end
    end
    error("Not a file or valid url: " .. fullUrl)
  end

  function core.sync(author, name)
    local hashes = {}
    local tags = {}
    local function check(author, name)
      local versions = {}
      for version in db.versions(author, name) do
        local match, hash = db.offlineMatch(author, name, version)
        versions[match] = hash
      end
      for version, hash in pairs(versions) do
        local match, newHash = db.match(author, name, version)
        if hash ~= newHash then
          hashes[#hashes + 1] = newHash
          tags[#tags + 1] = author .. "/" .. name .. "/v" .. match
        end
      end
      local match, hash = db.match(author, name)
      if match and not db.offlineMatch(author, name, match) then
        hashes[#hashes + 1] = hash
        tags[#tags + 1] = author .. "/" .. name .. "/v" .. match
      end
    end

    if author then
      if name then
        log("checking for updates", author .. '/' .. name)
        check(author, name)
      else
        log("checking for updates", author .. "/*")
        for name in db.names(author) do
          check(author, name)
        end
      end
    else
      log("checking for updates", "*/*")
      for author in db.authors() do
        for name in db.names(author) do
          check(author, name)
        end
      end
    end
    if #tags == 0 then return end
    log("syncing", table.concat(tags, ", "), "highlight")
    db.fetch(hashes)
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
