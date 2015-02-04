local uv = require('uv')

local co = coroutine.running()

local child = uv.spawn(uv.exepath(), {
  args = args,
  env = {
    "LUVI_APP=" .. uv.cwd()
  },
  stdio = {0,1,2}
}, function (...)
  coroutine.resume(co, ...)
end);

coroutine.yield()
