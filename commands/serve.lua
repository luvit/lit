local tcp = require('coro-tcp')
local httpCodec = require('http-codec')
local websocketCodec = require('websocket-codec')

local log = require('../lib/log')
local wrapper = require('../lib/wrapper')
local readWrap, writeWrap = wrapper.reader, wrapper.writer
local makeRemote = require('../lib/codec').makeRemote
local handlers = require('../lib/handlers')
local handleRequest = require('../lib/api')(args[2])

tcp.createServer("127.0.0.1", 4822, function (rawRead, rawWrite, socket)

  -- Handle the websocket handshake at the HTTP level
  local read, updateDecoder = readWrap(rawRead, httpCodec.decoder())
  local write, updateEncoder = writeWrap(rawWrite, httpCodec.encoder())

  local function upgrade(res)
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
    local success, err = xpcall(function ()
      for command, data in remote.read do
        log("client command", peerName .. " - " .. command)
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
  end

  for req in read do
    local res, err = websocketCodec.handleHandshake(req, "lit")
    if res then return upgrade(res) end
    local body = {}
    for chunk in read do
      if #chunk > 0 then
        body[#body + 1] = chunk
      else
        break
      end
    end
    body = table.concat(body)
    if req.method == "GET" or req.method == "HEAD" then
      req.body = #body > 0 and body or nil
      res, err = handleRequest(req)
    end
    if not res then
      write({code=400})
      write(err or "lit websocket request required")
      return write()
    end
    write(res)
    write(res.body)
  end

end)

-- Never return so that the command keeps running.
coroutine.yield()
