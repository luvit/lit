local uv = require('uv')

local client = uv.new_tcp()
uv.tcp_connect(client, "127.0.0.1", 4821, coroutine.wrap(function (err)
  assert(not err, err)
end))
