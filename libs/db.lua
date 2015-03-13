--[[

Mid Level Storage Commands
=========================

These commands work at a higher level and consume the low-level storage APIs.

db.has(hash) -> bool                   - check if db has an object
db.load(hash) -> raw                   - load raw data, nil if not found
db.loadAny(hash) -> kind, value        - pre-decode data, error if not found
db.loadAs(kind, hash) -> value         - pre-decode and check type or error
db.save(raw) -> hash                   - save pre-encoded and framed data
db.saveAs(kind, value) -> hash         - encode, frame and save to objects/$ha/$sh
db.hashes() -> iter                    - Iterate over all hashes

db.match(author, name, version)
  -> match, hash                       - Find the best version matching the query.
db.read(author, name, version) -> hash - Read from refs/tags/$author/$tag/v$version
db.write(author, name, version, hash)  - Write to refs/tags/$suthor/$tag/v$version
db.authors() -> iter                   - Iterate over refs/tags/*
db.names(author) -> iter               - Iterate nodes in refs/tags/$author/**
db.versions(author, name) -> iter      - Iterate leaves in refs/tags/$author/$tag/*

db.readKey(author, fingerprint) -> key - Read from keys/$author/$fingerprint
db.putKey(author, fingerprint, key)    - Write to keys/$author/$fingerprint
db.revokeKey(author, fingerprint)      - Delete keys/$author/$fingerprint
db.fingerprints(author) -> iter        - iter of fingerprints

db.getEtag(author) -> etag             - Read keys/$author.etag
db.setEtag(author, etag)               - Writes keys/$author.etag

db.owners(org) -> iter                 - Iterates lines of keys/$org.owners
db.isOwner(org, author) -> bool        - Check if a user is an org owner
db.addOwner(org, author)               - Add a new owner
db.removeOwner(org, author)            - Remove an owner

db.import(fs, path) -> kind, hash      - Import a file or tree into database
db.export(hash, path) -> kind          - Export a hash to a path
]]

return function (path)
  local storage = require('./storage')(path)
  local semver = require('semver')
  local normalize = semver.normalize
  local digest = require('openssl').digest.digest
  local deflate = require('miniz').deflate
  local inflate = require('miniz').inflate
  local pathJoin = require('luvi').path.join
  local fs = require('coro-fs')
  local git = require('git')
  local decoders = git.decoders
  local encoders = git.encoders
  local deframe = git.deframe
  local frame = git.frame
  local modes = git.modes
  local rules = require('rules')
  local compileFilter = rules.compileFilter
  local isAllowed = rules.isAllowed
  local filterTree = rules.filterTree

  local db = {}

  local function assertHash(hash)
    assert(hash and #hash == 40 and hash:match("^%x+$"), "Invalid hash")
  end

  local function hashPath(hash)
    return string.format("objects/%s/%s", hash:sub(1, 2), hash:sub(3))
  end

  function db.has(hash)
    assertHash(hash)
    return storage.read(hashPath(hash)) and true or false
  end

  function db.load(hash)
    assertHash(hash)
    local compressed, err = storage.read(hashPath(hash))
    if not compressed then return nil, err end
    return inflate(compressed, 1)
  end

  function db.loadAny(hash)
    local raw = assert(db.load(hash), "no such hash")
    local kind, value = deframe(raw)
    return kind, decoders[kind](value)
  end

  function db.loadAs(kind, hash)
    local actualKind, value = db.loadAny(hash)
    assert(kind == actualKind, "Kind mismatch")
    return value
  end

  function db.save(raw)
    local hash = digest("sha1", raw)
    -- 0x1000 = TDEFL_WRITE_ZLIB_HEADER
    -- 4095 = Huffman+LZ (slowest/best compression)
    storage.put(hashPath(hash), deflate(raw, 0x1000 + 4095))
    return hash
  end

  function db.saveAs(kind, value)
    if type(value) ~= "string" then
      value = encoders[kind](value)
    end
    return db.save(frame(kind, value))
  end

  function db.hashes()
    local groups = storage.nodes("objects")
    local prefix, iter
    return function ()
      while true do
        if prefix then
          local rest = iter()
          if rest then return prefix .. rest end
          prefix = nil
          iter = nil
        end
        prefix = groups()
        if not prefix then return end
        iter = storage.leaves("objects/" .. prefix)
      end
    end
  end

  function db.match(author, name, version)
    local match = semver.match(version, db.versions(author, name))
    if not match then return end
    return match, assert(db.read(author, name, match))
  end

  function db.read(author, name, version)
    version = normalize(version)
    local path = string.format("refs/tags/%s/%s/v%s", author, name, version)
    local hash = storage.read(path)
    if not hash then return end
    return hash:sub(1, 40)
  end

  function db.write(author, name, version, hash)
    version = normalize(version)
    assertHash(hash)
    local path = string.format("refs/tags/%s/%s/v%s", author, name, version)
    storage.write(path, hash .. "\n")
  end

  function db.authors()
    return storage.nodes("refs/tags")
  end

  function db.names(author)
    local prefix = "refs/tags/" .. author .. "/"
    local stack = {storage.nodes(prefix)}
    return function ()
      while true do
        if #stack == 0 then return end
        local name = stack[#stack]()
        if name then
          local path = stack[#stack - 1]
          local newPath = path and path .. "/" .. name or name
          stack[#stack + 1] = newPath
          stack[#stack + 1] = storage.nodes(prefix .. newPath)
          return newPath
        end
        stack[#stack] = nil
        stack[#stack] = nil
      end
    end
  end

  function db.versions(author, name)
    local path = string.format("refs/tags/%s/%s", author, name)
    local iter = storage.leaves(path)
    return function ()
      local item = iter()
      return item and item:sub(2)
    end
  end

  local function keyPath(author, fingerprint)
    return string.format("keys/%s/%s", author, fingerprint)
  end

   local function windowsSafeKeyPath(author, fingerprint)
    return string.format("keys/%s/%s", author, fingerprint:gsub(":", "_"))
  end

  function db.readKey(author, fingerprint)
    return storage.read(windowsSafeKeyPath(author, fingerprint))
  end

  function db.putKey(author, fingerprint, key)
    return storage.put(windowsSafeKeyPath(author, fingerprint), key)
  end

  function db.revokeKey(author, fingerprint)
    return storage.delete(windowsSafeKeyPath(author, fingerprint))
  end

  -- Wrapper around storage.leaves to replace every "_" with a ":" (Windows safe)
  function db.fingerprints(author)
    local n0 = 0

    return function()
      n0 = n0 + 1
      local n1 = 0

      for fingerprint in storage.leaves("keys/" .. author) do
        n1 = n1 + 1
        if n1 == n0 then
          return fingerprint:gsub("_", ":")
        end
      end

      return nil
    end
  end

  function db.getEtag(author)
    return storage.read("keys/" .. author .. ".etag")
  end

  function db.setEtag(author, etag)
    return storage.write("keys/" .. author .. ".etag", etag)
  end

  local function ownersPath(org)
    return "keys/" .. org .. ".owners"
  end

  function db.owners(org)
    local owners = storage.read(ownersPath(org))
    if not owners then return end
    return owners:gmatch("[^\n]+")
  end

  function db.isOwner(org, author)
    local iter = db.owners(org)
    if not iter then return false end
    for owner in iter do
      if author == owner then return true end
    end
    return false
  end

  function db.addOwner(org, author)
    if db.isOwner(org, author) then return end
    local path = ownersPath(org)
    local owners = storage.read(path)
    owners = (owners or "") .. author .. "\n"
    storage.write(path, owners)
  end

  function db.removeOwner(org, author)
    local list = {}
    for owner in db.owners(org) do
      if owner ~= author then
        list[#list + 1] = owner
      end
    end
    storage.write(ownersPath(org), table.concat(list, "\n") .. "\n")
  end


  function db.import(fs, path, rules, nativeOnly)
    if nativeOnly == nil then nativeOnly = false end
    local filters = {}
    if rules then
      filters[#filters + 1] = compileFilter(path, rules, nativeOnly)
    end

    local importEntry, importTree

    function importEntry(path, stat)
      if stat.type == "directory" then
        local hash = importTree(path)
        if not hash then return end
        return modes.tree, hash
      end
      if stat.type == "file" then
        if not stat.mode then
          stat = fs.stat(path)
        end
        local mode = bit.band(stat.mode, 73) > 0 and modes.exec or modes.file
        return mode, db.saveAs("blob", assert(fs.readFile(path)))
      end
      if stat.type == "link" then
        return modes.sym, db.saveAs("blob", assert(fs.readlink(path)))
      end
      error("Unsupported type at " .. path .. ": " .. tostring(stat.type))
    end

    function importTree(path)
      assert(type(fs) == "table")

      local items = {}
      local meta = fs.readFile(pathJoin(path, "package.lua"))
      if meta then meta = loadstring(meta)() end
      if meta and meta.files then
        filters[#filters + 1] = compileFilter(path, meta.files, nativeOnly)
      end

      for entry in assert(fs.scandir(path)) do
        local fullPath = pathJoin(path, entry.name)
        if isAllowed(fullPath, entry, filters) then
          entry.mode, entry.hash = importEntry(fullPath, entry)
          if entry.hash then
            items[#items + 1] = entry
          end
        end
      end
      return #items > 0 and db.saveAs("tree", items)
    end

    local mode, hash = importEntry(path, assert(fs.stat(path)))
    if not hash then return end
    return modes.toType(mode), hash
  end

  function db.export(hash, path, rules, nativeOnly)
    if nativeOnly == nil then nativeOnly = true end
    local kind, value = db.loadAny(hash)
    if not kind then error(value or "No such hash") end

    if kind == "tree" then
      hash = filterTree(db, path, hash, rules, nativeOnly)
      value = db.loadAs("tree", hash)
    end

    local exportEntry, exportTree

    function exportEntry(path, mode, value)
      if mode == modes.tree then
        exportTree(path, value)
      elseif mode == modes.sym then
        local success, err = fs.symlink(value, path)
        if not success and err:match("^ENOENT:") then
          assert(fs.mkdirp(pathJoin(path, "..")))
          assert(fs.symlink(value, path))
        end
      elseif modes.isFile(mode) then
        local success, err = fs.writeFile(path, value)
        if not success and err:match("^ENOENT:") then
          assert(fs.mkdirp(pathJoin(path, "..")))
          assert(fs.writeFile(path, value))
        end
        assert(fs.chmod(path, mode))
      else
        error("Unsupported mode at " .. path .. ": " .. mode)
      end
    end

    function exportTree(path, tree)

      assert(fs.mkdirp(path))
      for i = 1, #tree do
        local entry = tree[i]
        local fullPath = pathJoin(path, entry.name)
        local kind, value = db.loadAny(entry.hash)
        assert(modes.toType(entry.mode) == kind, "Git kind mismatch")
        exportEntry(fullPath, entry.mode, value)
      end
    end


    exportEntry(path, kind == "tree" and modes.tree or modes.blob, value)
    return kind
  end

  return db
end
