local uv = require('uv')

local co = coroutine.running()

local env = require('env')
local newEnv = {}
local keys = env.keys()
for i = 1, #keys do
  local key = keys[i]
  local value = env.get(key)
  if key ~= "LUVI_APP" then
    newEnv[#newEnv + 1] = key .. "=" .. value
  end
end
newEnv[#newEnv + 1] = "LUVI_APP=" .. uv.cwd()

local child = uv.spawn(uv.exepath(), {
  args = args,
  env = newEnv,
  stdio = {0,1,2}
}, function (...)
  coroutine.resume(co, ...)
end);

coroutine.yield()
