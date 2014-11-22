local git = require('./git')
local uv = require('uv')
local fs = require('fs')
local deflate = require('miniz').deflate
local inflate = require('miniz').inflate
local pathJoin = require('luvi').path.join

exports.base = pathJoin(uv.cwd(), "test.git")

local function hashToPath(hash)
  return pathJoin(exports.base, "objects", string.sub(hash, 1, 2), string.sub(hash, 3))
end

local function mkdir(path)
  local thread = coroutine.running()
  local success, err = fs.mkdir(path, thread)
  if err then
    if string.match(err, "^ENOENT:") then
      mkdir(pathJoin(path, ".."))
      success, err = fs.mkdir(path, thread)
    elseif string.match(err, "^EEXIST") then
      success, err = true, nil
    end
  end
  return success, err
end

function exports.save(type, value)
  local thread = coroutine.running()
  local hash, body = git.frame(type, value)
  local path = hashToPath(hash)
  mkdir(pathJoin(path, ".."))
  -- 4095=Huffman+LZ (slowest/best compression)
  -- TDEFL_WRITE_ZLIB_HEADER             = 0x01000,
  body = deflate(body, 0x01000 + 4095)
  fs.writeFile(path, body, thread)
  return hash
end

function exports.load(hash)
  local thread = coroutine.running()
  local path = hashToPath(hash)
  local body = inflate(fs.readFile(path, thread))
  p(body)
  error("TODO: parse")
end

function exports.writeRef(ref, hash)
  local path = pathJoin(exports.base, ref)
  mkdir(pathJoin(path, ".."))
  return fs.writeFile(path, hash .. "\n", coroutine.running())
end

function exports.setHead(ref)
  return fs.writeFile(pathJoin(exports.base, "HEAD"), "ref: " .. ref .. "\n", coroutine.running())
end

function exports.init()
  mkdir(exports.base)
  local path = pathJoin(exports.base, "config")
  return fs.writeFile(path, "[core]\n\trepositoryformatversion = 0\n\tfilemode = true\n\tbare = true\n", coroutine.running())
end
