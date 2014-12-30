local log = require('../lib/log')
local createServer = require('creationix/coro-tcp').createServer
local makeRemote = require('../lib/codec').makeRemote
local config = require('../lib/config')
local db = config.db

local handlers = {}

local function split(line)
  local args = {}
  for match in string.gmatch(line, "[^ ]+") do
    args[#args + 1] = match
  end
  return unpack(args)
end


function handlers.match(remote, data)
  local name, version = split(data)
  -- TODO: check for mismatch
  local match, hash = db.match(name, version)
  if not match and hash then
    error(hash)
  end
  remote.writeAs("reply", match and (match .. ' ' .. hash))
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

  local success, err = xpcall(function ()
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

coroutine.yield()
