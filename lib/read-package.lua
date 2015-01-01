local git = require('creationix/git')
local fs = require('creationix/coro-fs')
local pathJoin = require('luvi').path.join

local function makeAny()
  return setmetatable({},{
    __index = makeAny,
    __call = makeAny,
    __newindex = function () end,
  })
end

local sandbox = {
  __index = _G
}

function exports.eval(data, name)
  local fn = assert(loadstring(data, name))
  local exports = {}
  local module = { exports = exports }
  setfenv(fn, setmetatable({
    module = module,
    exports = exports,
    require = makeAny,
  }, sandbox))
  local success, ret = pcall(fn)
  assert(success, ret)
  local meta = type(ret) == "table" and ret or module.exports
  assert(meta, "Missing exports")
  assert(meta.name, "Missing name in package description")
  assert(meta.version, "Missing version in package description")
  return meta
end

-- Given a db instance and the package root hash return kind and meta. For
-- blobs, assume meta is in the file, for trees, look for package.lua and then
-- init.lua
function exports.read(db, hash)
  local kind, data
  data = assert(db.load(hash))
  kind, data = git.deframe(data)
  if kind == "tag" then
    local tag = git.decoders.tag(data)
    data = assert(db.load(tag.object))
    kind, data = git.deframe(data)
    assert(kind == tag.type)
  end
  if kind == "tree" then
    local tree = git.listToMap(git.decoders.tree(data))
    local packageHash
    local entry = tree["package.lua"]
    if entry and git.modes.isFile(entry.mode) then
      packageHash = entry.hash
    else
      entry = tree["init.lua"]
      if entry and git.modes.isFile(entry.mode) then
        packageHash = entry.hash
      end
    end
    assert(packageHash, "neither package.lua or init.lua found in package root")
    data = assert(db.load(packageHash))
    local packageKind
    packageKind, data = git.deframe(data)
    assert(packageKind == "blob")
  end

  return kind, exports.eval(data, "package:" .. hash)
end

function exports.readFs(path)
  local packagePath = path
  local data = fs.readFile(path)
  if not data then
    packagePath = pathJoin(path, "package.lua")
    data = fs.readFile(packagePath)
  end
  if not data then
    packagePath = pathJoin(path, "init.lua")
    data = fs.readFile(packagePath)
  end
  local meta = data and exports.eval(data, packagePath)
  if not meta then
    return nil, path .. " does not appear to be a lit package"
  end
  return meta, packagePath
end
