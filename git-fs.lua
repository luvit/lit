local digest = require('openssl').digest.digest
local git = require('./git')
local modes = git.modes
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
  ref = self:readFile(ref)
  ref = string.match(ref, "%x+")
  assert(#ref == 40, "Invalid hash in " .. ref)
  return ref
end

function repo:init()
  self:mkdir("objects")
  self:mkdir("refs/heads")
  self:mkdir("refs/tags")
  self:writeFile("HEAD", "ref: refs/heads/master\n")
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

function repo:import(base)
  -- Load the package config
  local configPath = pathJoin(base, "package.lua")
  local err, config = fs.readFile(configPath)
  assert(not err, err)
  config = assert(loadstring("return " .. config, configPath))
  config = assert(setfenv(config, {})())

  -- Compile the rules
  local rules
  if config.files then
    rules = {}
    for i = 1, #config.files do
      local file = config.files[i]
      local include = true
      if string.sub(file, 1, 1) == "!" then
        file = string.sub(file, 2)
        include = false
      end
      file = string.gsub(file, "[%^%$%(%)%.%[%]%+%-]", "%%%1")
      file = string.gsub(file, "%*%*?", function (m)
        return m == "**" and ".+"
                         or "[^/]+"
      end)
      file = "^" .. file .. "$"
      rules[i] = {
        include = include,
        pattern = file
      }
    end
  else
    -- Default to including only lua files
    rules = {{true, "^.*%.lua$"}}
  end

  local function importTree(path)
    local entries = {}
    fs.scandir(pathJoin(base, path), function (entry)
      local filename = pathJoin(path, entry.name)

      -- Apply the rules to see if this file should be included
      local include = entry.type == "DIR"
      for i = 1, #rules do
        if string.match(filename, rules[i].pattern) then
          include = rules[i].include
        end
      end
      if not include then return end

      local hash, mode
      if entry.type == "DIR" then
        hash = importTree(filename)
        mode = modes.tree
      else
        local fullPath = pathJoin(base, filename)
        local err, stat, body
        err, stat = fs.lstat(fullPath)
        assert(not err, err)
        if stat.type == "LINK" then
          mode = modes.sym
          err, body = fs.readlink(fullPath)
        else
          err, body = fs.readFile(fullPath)
          mode = (bit.band(stat.mode, 73) > 0) and modes.exec or modes.blob
        end
        assert(not err, err)
        hash = self:save(body, "blob")
      end

      -- Don't include empty trees
      if hash == "4b825dc642cb6eb9a060e54bf8d69288fbee4904" then return end

      entries[#entries + 1] = {
        name = entry.name,
        mode = mode,
        hash = hash,
      }
    end)
    return self:save(entries, "tree")
  end

  return importTree('.')
end

function repo:tag(name, version, hash)
  -- TODO: create annotated tag and sign using SSH private key
  local tagHash, body = git.frame({

  }, "tag")
  p{
    hash = tagHash,
    body = body
  }
end

-- TODO: port https://github.com/dominictarr/ssh-key-to-pem/blob/master/index.js to luvit


return function(base)
  return setmetatable({
    base = pathJoin(uv.cwd(), base)
  }, repoMeta)
end


