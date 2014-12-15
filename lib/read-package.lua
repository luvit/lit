local fs = require('creationix/coro-fs')

local function makeAny()
  return setmetatable({},{
    __index = makeAny
  })
end

return function (path)
  local exports = {}
  local module = {exports=exports}
  local contents, fn, err
  contents, err = fs.readFile(path)
  if not contents then return nil, err end
  fn = assert(loadstring(contents, path))
  if not fn then return nil, err end
  setfenv(fn, {
    setmetatable = setmetatable,
    require = makeAny,
    module = module,
    exports = exports,
  })
  local out = fn()
  return type(out) == "table" and out or module.exports
end
