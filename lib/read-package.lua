local fs = require('creationix/coro-fs')
local git = require('creationix/git')

local function makeAny()
  return setmetatable({},{
    __index = makeAny
  })
end

function exports.eval(data, name)
  local fn = assert(loadstring(data, name))
  local exports = {}
  local module = { exports = exports }
  setfenv(fn, {
    module = module,
    exports = exports,
    require = makeAny,
  })
  local success, ret = pcall(fn)
  assert(success, ret)
  local meta = ret or module.exports
  assert(meta.name, "Missing name in package description")
  assert(meta.version, "Missing version in package description")
  return meta
end

-- Given a storage instance and the package root hash return kind and meta. For
-- blobs, assume meta is in the file, for trees, look for package.lua and then
-- init.lua
function exports.readStorage(storage, hash)
  local kind, data
  data = assert(storage.load(hash))
  kind, data = git.deframe(data)
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
    data = assert(storage.load(packageHash))
    local packageKind
    packageKind, data = git.deframe(data)
    assert(packageKind == "blob")
  end

  return kind, exports.eval(data, "package:" .. hash)
end

function exports.readFs(path)
  error("TODO: implement package.readFs")
-- return function (path)
--   local exports = {}
--   local module = {exports=exports}
--   local contents, fn, err
--   contents, err = fs.readFile(path)
--   if not contents then return nil, err end
--   fn = assert(loadstring(contents, path))
--   if not fn then return nil, err end
--   setfenv(fn, {
--     setmetatable = setmetatable,
--     require = makeAny,
--     module = module,
--     exports = exports,
--   })
--   local out = fn()
--   return type(out) == "table" and out or module.exports
-- end

end

