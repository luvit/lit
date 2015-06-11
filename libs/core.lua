--[[

Copyright 2014-2015 The Luvit Authors. All Rights Reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS-IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

--]]

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
local encoders = git.encoders
local semver = require('semver')
local miniz = require('miniz')
local vfs = require('./vfs')
local fs = require('coro-fs')
local http = require('coro-http')
local exec = require('exec')
local prompt = require('prompt')(require('pretty-print'))
local luvi = require('luvi')
local makeDb = require('db')
local import = require('import')
local getInstalled = require('get-installed')
local calculateDeps = require('calculate-deps')
local queryFs = require('pkg').query
local installDeps = require('install-deps').toDb
local installDepsFs = require('install-deps').toFs
local exportZip = require('export-zip')

local function run(...)
  local stdout, stderr, code, signal = exec(...)
  if code == 0 and signal == 0 then
    return string.gsub(stdout, "%s*$", "")
  else
    return nil, string.gsub(stderr, "%s*$", "")
  end
end

local function luviUrl(meta)

  local arch
  if isWindows then
    if jit.arch == "x64" then
      arch = "Windows-amd64.exe"
    else
      arch = "Windows-ia32.exe"
    end
  else
    arch = run("uname", "-s") .. "_" .. run("uname", "-m")
  end
  meta = meta or {}

  return string.format(
    "https://github.com/luvit/luvi/releases/download/v%s/luvi-%s-%s",
    meta.version or luvi.version, meta.flavor or "regular", arch)
end

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

local autocore
local function makeCore(config)

  if not config then
    autocore = autocore or makeCore(require('autoconfig'))
    return autocore
  end

  assert(config.database, "config.database is required path to git database")

  local db = makeDb(config.database)
  if config.upstream then
    db = require('./rdb')(db, config.upstream)
  end
  local core = {
    config = config,
    db = db
  }

  local privateKey
  local function getKey()
    if not config.privateKey then return end
    if privateKey then return privateKey end
    local keyData = assert(fs.readFile(config.privateKey))
    privateKey = require('openssl').pkey.read(keyData, true)
    return privateKey
  end

  function core.add(path)
    local key = getKey()
    if not (key and config.name and config.email) then
      error("Please run `lit auth` to configure your username")
    end
    local fs
    fs, path = vfs(path)
    local meta = pkg.query(fs, path)
    if not meta then
      error("Not a package: " .. path)
    end
    local author, name, version = pkg.normalize(meta)
    if config.upstream then core.sync(author, name) end

    local kind, hash = import(db, fs, path)
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
      message = jsonStringify(meta)
    })
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
      local tag, _, hash = unpack(queue[i])
      if #queue == 1 or confirm(tag .. " -> " .. config.upstream .. "\nDo you wish to publish?") then
        log("publishing", tag, "highlight")
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

  local function makeZip(rootHash, target)
    log("creating binary", target, "highlight")
    local meta = pkg.queryDb(db, rootHash)

    local tempFile = target:gsub("[^/\\]+$", ".%1.temp")
    local fd = assert(uv.fs_open(tempFile, "w", 511)) -- 0777

    local binSize
    if meta.luvi and not (meta.luvi.flavor == "regular" and semver.gte(luvi.version, meta.luvi.version)) then
      local url = luviUrl(meta.luvi)
      log("downloading custom luvi", url)
      -- TODO: stream the binary and show progress
      local res, bin = http.request("GET", url, {})
      assert(res.code == 200, bin)
      binSize = #bin
      uv.fs_write(fd, bin, -1)
    else      -- Copy base binary
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
    end

    assert(uv.fs_write(fd, exportZip(db, rootHash, true), binSize))
    uv.fs_close(fd)
    assert(uv.fs_rename(tempFile, target))
    log("done building", target)
  end

  local function defaultTarget(meta)
    local target = meta.target or meta.name:match("[^/]+$")
    if isWindows then
      target = target .. ".exe"
    end
    return target
  end

  function core.make(source, target)
    local zfs
    -- Use vfs so that source can be a zip file or a folder.
    zfs, source = vfs(source)
    local meta = queryFs(zfs, source)
    target = target or defaultTarget(meta)
    local kind, hash = assert(import(core.db, zfs, source, {"-" .. target}, true))
    assert(kind == "tree", "Only tree packages are supported for now")
    local deps = getInstalled(zfs, source)
    calculateDeps(core.db, deps, meta.dependencies)
    hash = installDeps(core.db, hash, deps, true)
    return makeZip(hash, target)
  end

  local function makeGit(target, url)
    local path = (url:match("([^/]+).git$") or target or "app") .. ".git-clone"
    log("downloading repo", url)
    local stdout, stderr, code, signal = exec("git", "clone", "--depth=1", "--recursive", url, path)
    if code == 0 and signal == 0 then
      core.make(path, target)
    else
      error("Problem cloning: " .. stdout .. stderr)
    end
    assert(fs.rmrf(path))
  end

  local function makeHttp(target, url)
    log("downloading zip", url)
    local res, body = http.request("GET", url)
    assert(res.code == 200, body)
    local filename
    for i = 1, #res do
      local key, value = unpack(res[i])
      if key:lower() == "content-disposition" then
        filename = value:match("filename=\"?([^;\"]+)")
      end
    end

    local path = filename or (target or "app") .. ".zip"
    fs.writeFile(path, body)
    core.make(path, target)
    fs.unlink(path)
  end

  local function makeLit(target, author, name, version)
    local tag = author .. '/' .. name
    local match, hash = db.match(author, name, version)
    if not match then
      if version then tag = tag .. "@" .. version end
      error("No such lit package: " ..  tag)
    end
    tag = tag .. "@" .. match

    if db.fetch then
      db.fetch({hash})
    end
    local meta = pkg.queryDb(db, hash)
    if not meta then
      error("Not a valid package: " .. tag)
    end

    target = target or defaultTarget(meta)
    local deps = {}
    calculateDeps(core.db, deps, meta.dependencies)
    local tagObj = db.loadAs("tag", hash)
    if not tagObj.type == "tree" then
      error("Only tags pointing to trees are currently supported for make")
    end
    hash = installDeps(core.db, tagObj.object, deps, true)
    return makeZip(hash, target)
  end

  local aliases = {
    "^github://([^/]+)/([^/@]+)/?@(.+)$", "https://github.com/%1/%2/archive/%3.zip",
    "^github://([^/]+)/([^/]+)/?$", "https://github.com/%1/%2/archive/master.zip",
    "^gist://([^/]+)/(.+)/?$", "https://gist.github.com/%1/%2.git",
  }
  core.urlAilases = aliases

  local handlers = {
    "^(https?://[^#]+%.git)$", makeGit,
    "^(https?://[^#]+)$", makeHttp,
    "^(git://.*)$", makeGit,
    "^lit://([^/]+)/([^@]+)@v?(.+)$", makeLit,
    "^lit://([^/]+)/([^@]+)$", makeLit,
    "^([^@/]+)/([^@]+)@v?(.+)$", makeLit,
    "^([^@/]+)/([^@]+)$", makeLit,
    "^([^ :/@]+%@.*)$", makeGit,
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

  function core.installList(path, newDeps)
    local deps = getInstalled(fs, path)
    calculateDeps(core.db, deps, newDeps)
    installDepsFs(core.db, fs, path, deps, true)
    return deps
  end

  function core.installDeps(path)
    local meta = pkg.query(fs, path)
    if not meta.dependencies then
      log("no dependencies", path)
      return
    end
    return core.installList(path, meta.dependencies)
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

return makeCore
