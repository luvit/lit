local createServer = require('creationix/coro-tcp').createServer
local httpCodec = require('creationix/http-codec')
local websocketCodec = require('creationix/websocket-codec')
local wrapper = require('../lib/wrapper')
local readWrap = wrapper.reader
local writeWrap = wrapper.writer

createServer("0.0.0.0", 8080, function (rawRead, rawWrite, socket)
  local peerName = socket:getpeername()
  peerName = peerName.ip .. ':' .. peerName.port
  p("new client", peerName)

  -- Handle the websocket handshake
  local read = readWrap(rawRead, httpCodec.decoder())
  local write = writeWrap(rawWrite, httpCodec.encoder())
  local res, err = websocketCodec.handshake(read(), "lit")
  if not res then
    write({code=500})
    write(err or "websocket request required")
    return write()
  end
  write(res)

  -- Implement a websocket echo server
  read = readWrap(rawRead, websocketCodec.decode)
  write = writeWrap(rawWrite, websocketCodec.encode)
  for item in read do
    if item.opcode == 1 or item.opcode == 2 then
      p(item.payload)
      item.mask = nil
      write(item)
    end
  end
  write()

end)

coroutine.yield()
