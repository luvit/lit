local uv = require('uv')
local log = require('../lib/log')

local config = require('../lib/config')
local db = config.db
local wrapStream = require('creationix/coro-channel').wrapStream
local protocol = require('../lib/protocol')

local function handleClient(peerName, read, write)
  local proto = protocol(true, read, write)

  proto.on("want", function (hash)
    log("client want", hash)
    return proto.send("send", assert(db.load(hash)))
  end)

  proto.on("send", function (data)
    local hash = assert(db.save(data))
    log("client send", hash)
    return hash
  end)

  proto.on("match", function (name, version)
    log("client match", version and (name .. ' ' .. version) or name)
    error("test")
    return proto.send("reply", db.match(name, version))
  end)

  log("client connected", peerName)
  proto.start(function (err)
    if err then
      log("client error", err, "err")
    end
    log("client disconnected", peerName)
  end)

end

local function makeServer(name, ip, port)
  local server = uv.new_tcp()
  server:bind(ip, port)
  local address = server:getsockname()
  log(name .. " bind", address.ip .. ':' .. address.port)
  server:listen(256, function (err)
    if err then return log(name .. " connect error", err, "err") end
    local client = uv.new_tcp()
    server:accept(client)
    local peerName = client:getpeername()
    peerName = peerName.ip .. ':' .. peerName.port
    coroutine.wrap(xpcall)(function ()
      handleClient(peerName, wrapStream(client))
    end, function (message)
      client:write(message .. "\n")
      client:close()
      print(debug.traceback(message))
    end)
  end)
  return server
end

makeServer("server", "0.0.0.0", 4821)

coroutine.yield()
