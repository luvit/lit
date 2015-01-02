local log = require('../lib/log')
local createServer = require('creationix/coro-tcp').createServer
local makeRemote = require('../lib/codec').makeRemote
local config = require('../lib/config')
local db = config.db
local storage = db.storage
local git = require('creationix/git')
local digest = require('openssl').digest.digest

local handlers = {}

local function split(line)
  local args = {}
  for match in string.gmatch(line, "[^ ]+") do
    args[#args + 1] = match
  end
  return unpack(args)
end

function handlers.read(remote, data)
  local name, version = split(data)
  -- TODO: check for mismatch
  local hash = db.read(name, version)
  remote.writeAs("reply", hash)
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
    local data, err = db.load(hash)
    if not data then
      return remote.writeAs("error", err or "No such hash: " .. hash)
    end
    local kind, raw = git.deframe(data)
    if kind == 'tag' then
      local tag = git.decoders.tag(raw)
      log("client want", tag.tag)
    else
      log("client want", hash, "string")
    end
    remote.writeAs("send", data)
  end
end

function handlers.send(remote, data)
  local authorized = remote.authorized or {}
  local kind, raw = git.deframe(data)
  local hashes = {}

  local hash = digest("sha1", data)
  if kind == "tag" then
    if remote.tag then
      return remote.writeAs("error", "package upload already in progress: " .. remote.tag.tag)
    end
    local tag = git.decoders.tag(raw)
    -- TODO: verify signature
    tag.hash = hash
    remote.tag = tag
    remote.authorized = authorized
    hashes[#hashes + 1] = tag.object
  else
    if not authorized[hash] then
      return remote.writeAs('error', "Attempt to send unauthorized object: " .. hash)
    end
    authorized[hash] = nil
    if kind == "tree" then
      local tree = git.decoders.tree(raw)
      for i = 1, #tree do
        hashes[#hashes + 1] = tree[i].hash
      end
    end
  end
  assert(db.save(data) == hash)

  local wants = {}
  for i = 1, #hashes do
    local hash = hashes[i]
    if not storage.has(hash) then
      wants[#wants + 1] = hash
      authorized[hash] = true
    end
  end

  if #wants > 0 then
    remote.writeAs("wants", wants)
  elseif not next(authorized) then
    local tag = remote.tag
    local name, version = string.match(tag.tag, "(.*)/v(.*)")
    storage.writeTag(name, version, tag.hash)
    log("new package", tag.tag)
    remote.writeAs("done", tag.hash)
    remote.tag = nil
    remote.authorized = nil
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
