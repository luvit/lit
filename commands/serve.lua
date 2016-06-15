local args = {...}
return function ()
  local createServer = require('coro-net').createServer
  local uv = require('uv')
  local httpCodec = require('http-codec')
  local websocketCodec = require('websocket-codec')
  local wrapIo = require('coro-websocket').wrapIo

  local log = require('log').log
  local makeRemote = require('codec').makeRemote
  local core = require('core')()

  local handlers = require('handlers')(core)
  local handleRequest = require('api')(core.db, args[2])

  -- Ignore SIGPIPE if it exists on platform
  if uv.constants.SIGPIPE then
    uv.new_signal():start("sigpipe")
  end

  createServer({
    host = "0.0.0.0",
    port = 4822,
    decode = httpCodec.decoder(),
    encode = httpCodec.encoder(),
  }, function (read, write, socket, updateDecoder, updateEncoder, close)

    local function upgrade(res)
      write(res)

      -- Upgrade the protocol to websocket
      updateDecoder(websocketCodec.decode)
      updateEncoder(websocketCodec.encode)
      read, write = wrapIo(read, write, { mask = false })

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
        remote.close()
      end, debug.traceback)
      if not success then
        log("client error", err, "err")
        remote.writeAs("error", string.match(err, ":%d+: *([^\n]*)"))
        remote.close()
      end
      log("client disconnected", peerName)
    end

    for req in read do
      local body = {}
      for chunk in read do
        if #chunk == 0 then break end
        body[#body + 1] = chunk
      end
      local res, err = websocketCodec.handleHandshake(req, "lit")
      if res then return upgrade(res) end
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
        write()
        if not socket:is_closing() then
          socket:close()
        end
        return
      end
      write(res)
      write(res.body)
    end
    write()

  end)

  -- Never return so that the command keeps running.
  coroutine.yield()
end
