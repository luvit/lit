local digest = require('openssl').digest.digest
local git = require('./git')
local fs = require('./fs')
local uv = require('uv')
local deflate = require('miniz').deflate
local inflate = require('miniz').inflate
local pathJoin = require('luvi').path.join


local repo = {}
local repoMeta = { __index = repo }


function repo:fullPath(path)
  -- Convert to a safe path by resolving internal special paths
  -- And ensuring it's a relative path.
  path = "./" .. pathJoin(path)
  -- Then add in the base.  The two steps keeps paths inside base.
  return pathJoin(self.base, path)
end

function repo:mkdir(path)
  path = self:fullPath(path)
  local err = fs.mkdir(path)
  if not err then return end
  if string.match(err, "^ENOENT:") then

    mkdir(pathJoin(path, ".."))
      success, err = fs.mkdir(path, thread)
    elseif string.match(err, "^EEXIST") then
      return
    else
      error(err)
    end
  end
end
local function mkdir(path)
end

local function writeFile(path, data)
  local _, err = fs.writeFile(path, data, coroutine.running())
  if err then
    return nil, err
  else
    return true
  end
end

local function readFile(path)
  return fs.readFile(path, coroutine.running())
end


function repo:hashToPath(hash)
  return pathJoin(self.base, "objects", string.sub(hash, 1, 2), string.sub(hash, 3))
end

function repo:resolveHash(ref)
  if string.match(ref, "^%x+$") then return ref end
  if ref == "HEAD" then
    ref = assert(readFile(pathJoin(self.base, "HEAD")))
    ref = string.match(ref, "ref: ([^\n]+)")
  end
  p({ref=ref})
  ref = assert(readFile(pathJoin(self.base, ref)))
  ref = string.match(ref, "%x+")
  return ref
end

function repo:init()
  assert(mkdir(pathJoin(self.base, "objects")))
  assert(mkdir(pathJoin(self.base, "refs/heads")))
  assert(mkdir(pathJoin(self.base, "refs/tags")))
  local path = pathJoin(self.base, "config")
  local data = "[core]\n"
            .. "\trepositoryformatversion = 0\n"
            .. "\tfilemode = true\n"
            .. "\tbare = true\n"
  assert(writeFile(path, data))
end

function repo:save(value, kind)
  local hash, body = git.frame(value, kind)
  local path = self:hashToPath(hash)
  assert(mkdir(pathJoin(path, "..")))
  -- TDEFL_WRITE_ZLIB_HEADER             = 0x01000,
  -- 4095=Huffman+LZ (slowest/best compression)
  body = deflate(body, 0x01000 + 4095)
  assert(writeFile(path, body))
  return hash
end

function repo:writeRef(ref, hash)
  if ref ~= git.safe(ref) then
    error("Illegal ref: " .. ref)
  end
  local path = pathJoin(self.base, ref)
  assert(mkdir(pathJoin(path, "..")))
  assert(writeFile(path, hash .. "\n"))
end

function repo:setHead(ref)
  if ref ~= git.safe(ref) then
    error("Illegal ref: " .. ref)
  end
  local path = pathJoin(self.base, "HEAD")
  return writeFile(path, "ref: " .. ref .. "\n")
end

function repo:load(hash)
  hash = self:resolveHash(hash)
  local path = self:hashToPath(hash)
  local body = assert(readFile(path))
  body = inflate(body, 1)
  assert(hash == digest("sha1", body), "hash mismatch")
  return git.deframe(body)
end

return function(base)
  return setmetatable({
    base = pathJoin(uv.cwd(), base)
  }, repoMeta)
end


