local makeChroot = require('creationix/coro-fs').chroot
local semver = require('creationix/semver')
local digest = require('openssl').digest.digest
local pathJoin = require('luvi').path.join
local deflate = require('miniz').deflate
local inflate = require('miniz').inflate

local function hashToPath(hash)
  assert(#hash == 40 and string.match(hash, "^%x+$"))
  return pathJoin("objects", string.sub(hash, 1, 2), string.sub(hash, 3))
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

  --[[
  storage.read(tag) -> hash
  -------------------------

  Given a full tag (name and version), return the hash or nil for no such match.
  ]]--
  function storage.read(tag)
    local raw, err = fs.readFile(pathJoin("refs/tags/", tag))
    if not raw then
      if string.match(err, "^ENOENT:") then return end
      return nil, err
    end
    return raw and string.match(raw, "%x+")
  end

  --[[
  storage.write(tag, hash)
  ------------------------

  Write the hash for a full tag (name and version). Fails if the tag already
  exists.
  ]]--
  function storage.write(tag, hash)
    local path = pathJoin("refs/tags/", tag)
    local fd, success, err
    while true do
      fd, err = fs.open(path, "wx")
      if fd then break end
      if string.match(err, "^ENOENT:") then
        fs.mkdirp(pathJoin(path, ".."))
      else
       return nil, err
      end
    end
    local data = hash .. "\n"
    success, err = fs.write(fd, data)
    fs.fchmod(fd, 256)
    fs.close(fd)
    return success, err
  end

  --[[
  storage.versions(name) -> iterator<version>
  -------------------------------------------

  Given a package name, return an iterator of versions or nil if no such
  package.
  ]]
  function storage.versions(name)
    local iter, err = fs.scandir(pathJoin("refs/tags", name))
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

  return storage

end
