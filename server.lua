local uv = require('uv')
local fs = require('./fs')
local db = require('./git-fs')("test.git")
local decoder = require('./net-decoder')
local encoders = require('./net-encoders')

local handlers = {}
local server = uv.new_tcp()
uv.tcp_bind(server, "0.0.0.0", 4821)
uv.listen(server, 128, coroutine.wrap(function (err)

  assert(not err, err)
  local client = uv.new_tcp()
  uv.accept(server, client)
  local buffer = ""
  uv.read_start(client, function (err, chunk)
    assert(not err, err)
    buffer = buffer .. chunk
    while #buffer > 0 do
      local event, extra = decoder(buffer)
      if not event then break end
      buffer = extra
      handlers[event[1]](unpack(event, 2))
    end
  end)
end))
print("db sync server listening on port 4821")

function handlers.send(raw)
  p("SEND", raw)
end

function handlers.wants(wants)
  p("WANTS", wants)
end

function handlers.nope(hash)
  p("NOPE", hash)
end

function handlers.give(token, hash)
  p("GIVE", token, hash)
end

function handlers.got(hash)
  p("GOT", hash)
end

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
