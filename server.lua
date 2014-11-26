local uv = require('uv')
local decoder = require('./net-decoder')
local encoders = require('./net-encoders')

local serverSession

local server = uv.new_tcp()
uv.tcp_bind(server, "0.0.0.0", 4821)
uv.listen(server, 128, coroutine.wrap(function (err)
  assert(not err, err)
  local client = uv.new_tcp()
  uv.accept(server, client)

  local events = {}
  local buffer = ""
  local paused = true
  local waiting = false
  local thread

  local function onChunk(err, chunk)
    assert(not err, err)
    buffer = buffer .. chunk
    while #buffer > 0 do
      local event, extra = decoder(buffer)
      if not event then break end
      buffer = extra
      if waiting then
        waiting = false
        assert(coroutine.resume(thread, event))
      else
        events[#events + 1] = event
        if not paused and #events > 2 then
          paused = true
          uv.read_stop(client)
        end
      end
    end
  end

  thread = coroutine.create(serverSession)
  coroutine.resume(thread, function ()
    if paused and #events < 3 then
      paused = false
      uv.read_start(client, onChunk)
    end
    if #events > 0 then
      return unpack(table.remove(events))
    end
    waiting = true
    return unpack(coroutine.yield())
  end, function (...)
    p("TODO: write", ...)
  end)

end))
print("db sync server listening on port 4821")


function serverSession(read, write)
  for command, data in read do
    p("Command", command, data)
  end
  p("END")
end

----------------------------------------------------------

local digest = require('openssl').digest.digest

local client = uv.new_tcp()
uv.tcp_connect(client, "127.0.0.1", 4821, coroutine.wrap(function (err)
  assert(not err, err)
  uv.read_start(client, function (err, data)
    p("Response from server", {err=err,data=data})
  end)
  uv.write(client, encoders.send("Hello World\n"))
  uv.write(client, encoders.give({
    token = digest("sha1", "secret token"),
    hash = digest("sha1", "tag content")
  }))
end))


