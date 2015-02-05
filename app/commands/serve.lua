local tcp = require('coro-tcp')
local httpCodec = require('http-codec')
local websocketCodec = require('websocket-codec')

local log = require('../lib/log')
local wrapper = require('../lib/wrapper')
local readWrap, writeWrap = wrapper.reader, wrapper.writer
local makeRemote = require('../lib/codec').makeRemote
local handlers = require('../lib/handlers')

tcp.createServer("127.0.0.1", 4822, function (rawRead, rawWrite, socket)

  -- Handle the websocket handshake at the HTTP level
  local read, updateDecoder = readWrap(rawRead, httpCodec.decoder())
  local write, updateEncoder = writeWrap(rawWrite, httpCodec.encoder())
  local req = read()
  if not req then
    return write()
  end
  local res, err = websocketCodec.handleHandshake(req, "lit")
  if not res then
    write({code=400})
    write(err or "lit websocket request required")
    return write()
  end
  write(res)

  -- Upgrade the protocol to websocket
  updateDecoder(websocketCodec.decode)
  updateEncoder(websocketCodec.encode)

  -- Log the client connection
  local peerName = socket:getpeername()
  peerName = peerName.ip .. ':' .. peerName.port
  log("client connected", peerName)

  -- Proces the client using server handles
  local remote = makeRemote(read, write)
  local success
  success, err = xpcall(function ()
    for command, data in remote.read do
      local handler = handlers[command]
      if handler then
        handler(remote, data)
      else
        remote.writeAs("error", "no such command " .. command)
      end
    end
  end, debug.traceback)
  if not success then
    log("client error", err, "err")
    remote.writeAs("error", string.match(err, ":%d+: *([^\n]*)"))
    remote.close()
  end

  log("client disconnected", peerName)


end)

-- Never return so that the command keeps running.
coroutine.yield()
