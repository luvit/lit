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
  p("mkdir", path)
  local fullPath = self:fullPath(path)
  local err = fs.mkdir(fullPath)
  if not err or string.match(err, "^EEXIST") then
    return
  end
  if string.match(err, "^ENOENT:") then
    self:mkdir(pathJoin(path, ".."))
    err = fs.mkdir(fullPath)
  end
  assert(not err, err)
end

function repo:writeFile(path, data)
  path = self:fullPath(path)
  local err = fs.writeFile(path, data)
  assert(not err, err)
end

function repo:readFile(path)
  path = self:fullPath(path)
  local err, data = fs.readFile(path)
  assert(not err, err)
  return data
end


local function hashToPath(hash)
  return pathJoin("objects", string.sub(hash, 1, 2), string.sub(hash, 3))
end

function repo:resolveHash(ref)
  if string.match(ref, "^%x+$") then return ref end
  if ref == "HEAD" then
    ref = self:readFile("HEAD")
    ref = string.match(ref, "ref: ([^\n]+)")
  end
  p({ref=ref})
  ref = self:readFile(ref)
  ref = string.match(ref, "%x+")
  return ref
end

function repo:init()
  self:mkdir("objects")
  self:mkdir("refs/heads")
  self:mkdir("refs/tags")
  self:writeFile("config", "[core]\n"
    .. "\trepositoryformatversion = 0\n"
    .. "\tfilemode = true\n"
    .. "\tbare = true\n")
end

function repo:save(value, kind)
  local hash, body = git.frame(value, kind)
  local path = hashToPath(hash)
  self:mkdir(pathJoin(path, ".."))
  -- TDEFL_WRITE_ZLIB_HEADER             = 0x01000,
  -- 4095=Huffman+LZ (slowest/best compression)
  body = deflate(body, 0x01000 + 4095)
  self:writeFile(path, body)
  return hash
end

function repo:writeRef(ref, hash)
  if ref ~= git.safe(ref) then
    error("Illegal ref: " .. ref)
  end
  self:mkdir(pathJoin(ref, ".."))
  self:writeFile(ref, hash .. "\n")
end

function repo:setHead(ref)
  if ref ~= git.safe(ref) then
    error("Illegal ref: " .. ref)
  end
  self:writeFile("HEAD", "ref: " .. ref .. "\n")
end

function repo:load(hash)
  hash = self:resolveHash(hash)
  local path = hashToPath(hash)
  local body = self:readFile(path)
  body = inflate(body, 1)
  assert(hash == digest("sha1", body), "hash mismatch")
  return git.deframe(body)
end

return function(base)
  return setmetatable({
    base = pathJoin(uv.cwd(), base)
  }, repoMeta)
end


