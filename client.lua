local uv = require('uv')
local encoders = require('./net-encoders')
local digest = require('openssl').digest.digest

local client = uv.new_tcp()
uv.tcp_connect(client, "127.0.0.1", 4821, coroutine.wrap(function (err)
  assert(not err, err)
  uv.read_start(client, function (err, data)
    p{err=err,data=data}
  end)
  uv.write(client, encoders.send("Hello World\n"))
  local token = digest("sha1", "secret token")
  local hash = digest("sha1", "tag content")
  uv.write(client, encoders.give(token, hash))
end))
