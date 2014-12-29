local log = require('../lib/log')
local createServer = require('../lib/coro-tcp').createServer
local makeRemote = require('../lib/codec').makeRemote
local config = require('../lib/config')
local db = config.db

local handlers = {}

function handlers.match(remote, data)
  local name, version = string.match(data, "^([^ ]+) (.*)$")
  -- TODO: check for mismatch
  local match, hash = db.match(name, version)
  -- TODO: check for mismatch
  remote.writeAs("reply", match .. ' ' .. hash)
end

function handlers.wants(remote, hashes)
  for i = 1, #hashes do
    local hash = hashes[i]
    local data = db.load(hash)
    -- TODO: check for mismatch
    remote.writeAs("send", data)
  end
end

createServer("0.0.0.0", 4821, function (read, write, socket)
  local peerName = socket:getpeername()
  peerName = peerName.ip .. ':' .. peerName.port
  local remote = makeRemote(read, write)

  log("client connected", peerName)

  for command, data in remote.read do
    local handler = handlers[command]
    if handler then
      handler(remote, data)
    else
      remote.writeAs("error", "no such command " .. command)
    end
  end

end)

coroutine.yield()
