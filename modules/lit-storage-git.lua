local Object = require('core').Object
local makeChroot = require('coro-fs').chroot
local digest = require('openssl').digest.digest
local pathJoin = require('luvi').path.join
local deflate = require('miniz').deflate
local inflate = require('miniz').inflate

local Storage = Object:extend()

function Storage:initialize(dir)
  self.dir = dir
  local fs = makeChroot(dir)
  self.fs = fs
  if not fs.access("HEAD") then
    assert(fs.mkdirp("objects"))
    assert(fs.mkdirp("refs/tags"))
    assert(fs.writeFile("HEAD", "ref: refs/heads/master\n"))
    assert(fs.writeFile("config", "[core]\n"
      .. "\trepositoryformatversion = 0\n"
      .. "\tfilemode = true\n"
      .. "\tbare = true\n"))
  end
end

local function hashToPath(hash)
  assert(#hash == 40 and string.match(hash, "^%x+$"))
  return pathJoin("objects", string.sub(hash, 1, 2), string.sub(hash, 3))
end

-- Save a binary blob to disk, returns the sha1 hash of the value
-- value is a string.
function Storage:save(value)
  local hash = digest("sha1", value)
  local path = hashToPath(hash)
  local fd, success, err
  while true do
    fd, err = self.fs.open(path, "wx")
    if fd then break end
    if string.match(err, "^EEXIST:") then return hash end
    if not string.match(err, "^ENOENT:") then return nil, err end
    self.fs.mkdirp(pathJoin(path, ".."))
  end
  -- TDEFL_WRITE_ZLIB_HEADER             = 0x01000,
  -- 4095=Huffman+LZ (slowest/best compression)
  value = deflate(value, 0x01000 + 4095)
  success, err = self.fs.write(fd, value)
  self.fs.fchmod(fd, 256)
  self.fs.close(fd)
  if success then
    return hash
  end
  return nil, err
end

function Storage:load(hash)
  local path = hashToPath(hash)
  local value, err = self.fs.readFile(path)
  if err then return nil, err end
  if not value then return end
  value = inflate(value, 1)
  if hash ~= digest("sha1", value) then
    return nil, "value doesn't match hash: " .. hash
  end
  return value
end

function Storage:read(tag)
  local raw = self.fs.readFile(pathJoin("refs/tags/", tag))
  return string.match(raw, "%x+")
end

function Storage:write(tag, hash)
  local path = pathJoin("refs/tags/", tag)
  self.fs.mkdirp(pathJoin(path, ".."))
  return self.fs.writeFile(path, hash .. "\n")
end

function Storage:begin()
  -- TODO: Implement
end

function Storage:commit()
  -- TODO: Implement
end

function Storage:rollback()
  -- TODO: Implement
end

return function (dir)
  return Storage:new(dir)
end
