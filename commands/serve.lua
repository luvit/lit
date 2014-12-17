local uv = require('uv')
local log = require('../lib/log')

local encoder = require('../lib/encoder')
local decoder = require('../lib/decoder')
local config = require('../lib/config')
local thread = coroutine.running()


local function handleClient(client)
  local peerName = client:getpeername()
  peerName = peerName.ip .. ':' .. peerName.port
  local sockName = client:getsockname()
  sockName = sockName.ip .. ':' .. sockName.port
  log("client connect", sockName .. " <- " .. peerName)

  local commands = {}

  -- Setup a protocol decoder for the server
  local decode = decoder(true)
  local buffer = ""
  local function onRead(err, chunk)
    local success, message = xpcall(function ()
      assert(not err, err)
      if not chunk then
        log("client disconnect", peerName)
        return client:close()
      end
      buffer = buffer .. chunk
      repeat
        local extra, type, data = decode(buffer)
        if extra then
          buffer = extra
          commands[type](data)
        end
      until not extra or #buffer == 0
    end, debug.traceback or function (message)
      return string.match(message, "%][^ ]* (.*)") or message
    end)
    if not success then
      log("client error", peerName .. ' ' .. message)
      client:write(message .. "\n")
      return client:close()
    end
  end

  local function send(type, value)
    client:write(encoder[type](value))
  end

  function commands.handshake(versions)
    if not versions[0] then
      error("Server only supports lit protocol version 0")
    end
    send("agreement", 0)
  end

  function commands.query(query)
    p("query", query)
  end

  client:read_start(onRead)
end

local function makeServer(name, ip, port)
  local server = uv.new_tcp()
  server:bind(ip, port)
  local address = server:getsockname()
  log(name .. " ip", address.ip)
  log(name .. " port", address.port)
  server:listen(256, function (err)
    if err then return log(name .. " connect error", err, "err") end
    local client = uv.new_tcp()
    server:accept(client)
    handleClient(client)
  end)
  return server
end

makeServer("external", "0.0.0.0", 4821)
makeServer("internal", "::", 4822)

coroutine.yield()
