return function ()
  local createServer = require('coro-net').createServer
  local uv = require('uv')
  local httpCodec = require('http-codec')
  local websocketCodec = require('websocket-codec')

  local log = require('log').log
  local wrapper = require('coro-wrapper')
  local readWrap, writeWrap = wrapper.reader, wrapper.writer
  local makeRemote = require('codec').makeRemote
  local core = require('core')()

  local handlers = require('handlers')(core)
  local handleRequest = require('api')(core.db, args[2])

  -- Ignore SIGPIPE if it exists on platform
  if uv.constants.SIGPIPE then
    uv.new_signal():start("sigpipe")
  end

  createServer(4822, function (rawRead, rawWrite, socket)

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
        local now = uv.now()
        res, err = handleRequest(req)
        local delay = (uv.now() - now) .. "ms"
        res[#res + 1] = {"X-Request-Time", delay}
        print(req.method .. " " .. req.path .. " " .. res.code .. " " .. delay)
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
end
