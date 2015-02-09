local makeChroot = require('coro-fs').chroot
local semver = require('semver')
local digest = require('openssl').digest.digest
local pathJoin = require('luvi').path.join
local deflate = require('miniz').deflate
local inflate = require('miniz').inflate

local function hashToPath(hash)
  assert(#hash == 40 and string.match(hash, "^%x+$"))
  return pathJoin("objects", string.sub(hash, 1, 2), string.sub(hash, 3))
end

local function tagPath(name, version)
  return pathJoin("refs/tags", name, "v" .. version)
end

local function keyPath(author, fingerprint)
  return pathJoin("keys", author, (string.gsub(fingerprint, ":", "")))
end

return function (dir)

  local storage = {}

  local fs = makeChroot(dir)

  -- Initialize the git file storage tree if it does't exist yet
  if not fs.access("HEAD") then
    assert(fs.mkdirp("objects"))
    assert(fs.mkdirp("refs/tags"))
    assert(fs.writeFile("HEAD", "ref: refs/heads/master\n"))
    assert(fs.writeFile("config", "[core]\n"
      .. "\trepositoryformatversion = 0\n"
      .. "\tfilemode = true\n"
      .. "\tbare = true\n"))
  end

  --[[
  storage.has(hash) -> boolean
  ----------------------------

  Quick check to see if a hash is in the database already.
  ]]
  function storage.has(hash)
    local path = hashToPath(hash)
    return fs.access(path, "r")
  end

  --[[
  storage.load(hash) -> data
  --------------------------

  Load raw data by hash, verify hash before returning.
  ]]
  function storage.load(hash)
    local path = hashToPath(hash)
    local data, err = fs.readFile(path)
    if err then
      if string.match(err, "^ENOENT:") then return end
      return nil, err
    end
    if not data then return end
    data = inflate(data, 1)
    if hash ~= digest("sha1", data) then
      return nil, "hash mismatch"
    end
    return data
  end

  --[[
  storage.save(data) -> hash
  --------------------------

  Save raw data and return hash
  ]]--
  function storage.save(data)
    local hash = digest("sha1", data)
    local path = hashToPath(hash)
    local fd, success, err
    while true do
      fd, err = fs.open(path, "wx")
      if fd then break end
      if string.match(err, "^EEXIST:") then return hash end
      if not string.match(err, "^ENOENT:") then return nil, err end
      fs.mkdirp(pathJoin(path, ".."))
    end
    -- TDEFL_WRITE_ZLIB_HEADER             = 0x01000,
    -- 4095=Huffman+LZ (slowest/best compression)
    data = deflate(data, 0x01000 + 4095)
    success, err = fs.write(fd, data)
    fs.fchmod(fd, 256)
    fs.close(fd)
    if success then
      return hash
    end
    return nil, err
  end

  local function read(path)
    local raw, err = fs.readFile(path)
    if not raw then
      if string.match(err, "^ENOENT:") then return end
      return nil, err
    end
    return raw and raw:gsub("%s+$", "")
  end

  local function write(path, value)
    local fd, success, err
    while true do
      fd, err = fs.open(path, "w")
      if fd then break end
      if string.match(err, "^ENOENT:") then
        fs.mkdirp(pathJoin(path, ".."))
      else
       return nil, err
      end
    end
    local data = value .. "\n"
    success, err = fs.write(fd, data)
    fs.fchmod(fd, 384)
    fs.close(fd)
    return success, err
  end

  --[[
  storage.readTag(name, version) -> hash
  -------------------------

  Given a full name and version, return the hash or nil for no such match.
  ]]--
  function storage.readTag(name, version)
    return read(tagPath(name, version))
  end

  --[[
  storage.writeTag(name, version, hash
  ------------------------

  Write the hash for a full tag (name and version). Fails if the tag already
  exists.

  ]]--
  function storage.writeTag(name, version, hash)
    return write(tagPath(name, version), hash)
  end

  function storage.readKey(author, fingerprint)
    return read(keyPath(author, fingerprint))
  end

  function storage.writeKey(author, fingerprint, key)
    return write(keyPath(author, fingerprint), key)
  end

  function storage.revokeKey(author, fingerprint)
    return fs.unlink(keyPath(author, fingerprint))
  end

  --[[
  storage.versions(name) -> iterator<version>
  -------------------------------------------

  Given a package name, return an iterator of versions or nil if no such
  package.
  ]]
  function storage.versions(name)
    local iter, err = fs.scandir("refs/tags/" .. name)
    if not iter then
      if string.match(err, "^ENOENT:") then return end
      return nil, err
    end
    return function ()
      repeat
        local entry = iter()
        if entry and entry.type == "file" then
          return semver.normalize(entry.name)
        end
      until not entry
    end
  end

  --[[
  storage.fingerprints(author) -> iterator<fingerprint>
  -------------------------------------------

  Given a author name, return an iterator of fingerprints or nil if no such
  package.
  ]]
  function storage.fingerprints(author)
    local iter, err = fs.scandir("keys/" .. author)
    if not iter then
      if string.match(err, "^ENOENT:") then return end
      return nil, err
    end
    return function ()
      repeat
        local entry = iter()
        if entry and entry.type == "file" and entry.name ~= "etag" then
          local parts = {}
          for part in entry.name:gmatch("..") do
            parts[#parts + 1] = part
          end
          return table.concat(parts, ":")
        end
      until not entry
    end
  end

  return storage

end
