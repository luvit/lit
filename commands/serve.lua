local uv = require('uv')
local log = require('../lib/log')

local semver = require('creationix/semver')
local git = require('creationix/git')
local digest = require('openssl').digest.digest
local config = require('../lib/config')
local db = config.db

local codec = require('../lib/codec')



local function handleClient(peerName, read, write)
  -- log("client connect", peerName)

  local commands = {}
  local waiting = nil

  coroutine.wrap(xpcall)(function ()

    -- Process the protocol handshake
    local command, versions = read()
    assert(command == "handshake", "Expected handshake")
    if not versions[0] then
      error("Server only supports lit protocol version 0")
    end
    write("agreement", 0)

    -- log("client handshake", peerName)

    -- Process commands till the client disconnects
    for command, value in read do
      log("request", command .. ' ' .. tostring(value))
      local fn = commands[command]
      if not fn then error("Unsupported command: " .. command) end
      if command == "send" or command == "wants" then
        fn(value)
      else
        local parts = {}
        for part in string.gmatch(value, "[^ ]+") do
          parts[#parts + 1] = part
        end
        write("reply", fn(unpack(parts)))
      end
    end

    write()
    log("client disconnect", peerName)

  end, function (err)
    log("client error", peerName .. "\n" .. debug.traceback(err), "failure")
    write("error", (string.match(err, "%][^ ]+ (.*)") or err) .. "\n")
    write()
  end)

  function commands.MATCH(name, version)
    return {db.match(name, version)}
  end

  function commands.READ(name, version)
    return db.read(name, version)
  end

  function commands.PUSH(hash)
    p("PUSH", hash)
    local queue = {hash}
    repeat
      local hash = table.remove(queue)
      waiting = coroutine.running()
      write("want", hash)
      coroutine.yield()
    until #queue == 0
    return true
  end

  local authorized = {}
  function commands.send(data)
    local hash = digest("sha1", data)
    local valid = authorized[hash]
    if not valid then
      local raw, kind = git.deframe(data, true)
      if kind == "tag" then
        valid = true
        -- TODO: verify signature
      end
    end
    if valid then
      return assert(hash == storage:save(data))
    end
    error("Unauthorized send")
  end

  function commands.want(hash)
    local data = assert(db.load(hash))
    write("send", data)
  end

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
    handleClient(peerName, codec(true, client))
  end)
  return server
end

makeServer("server", "0.0.0.0", 4821)

coroutine.yield()
