local uv = require('uv')
local Object = require('core').Object
local digest = require('openssl').digest.digest
local codec = require('./codec')
local log = require('./log')

local function makeCallback()
  local thread = coroutine.running()
  return function (err, data)
    if err then
      return assert(coroutine.resume(thread, nil, err))
    end
    return assert(coroutine.resume(thread, data or true))
  end
end

local function connect(host, port)
  local res, success, err
  uv.getaddrinfo(host, port, { socktype = "stream" }, makeCallback())
  res, err = coroutine.yield()
  if not res then return nil, err end
  local socket = uv.new_tcp()
  socket:connect(res[1].addr, res[1].port, makeCallback())
  success, err = coroutine.yield()
  if not success then return nil, err end
  return socket
end

local Storage = Object:extend()

function Storage:initialize(host, port)
  local socket = assert(connect(host, port or 4821))
  local read, write = codec(false, socket)
  self.read = read
  self.write = write
  self.callbacks = {}

  -- Handshake with the remote server
  write("handshake", {0})
  local command, data = read()
  -- Make sure the server is speaking protocol v0
  assert(command == "agreement" and data == 0)

  coroutine.wrap(xpcall)(function ()
    for command, data in read do
      if command == "reply" and self.waiting then
        local thread = self.waiting
        self.waiting = nil
        assert(coroutine.resume(thread, data))
      elseif command == "send" then
        local hash = digest("sha1", data)
        local callback = self.callbacks[hash]
        assert(callback, "Unexpected value sent!")
        self.callbacks[hash] = nil
        callback(nil, data)
      else
        p(command, data)
      end
    end
  end, function (message)
    error(debug.traceback(message))
  end)
end

-- Save a binary blob to remote, returns the sha1 hash of the value
-- value is a string.
function Storage:save(value)
  self.write("send", value)
  local hash = digest("sha1", value)
  log("save", hash)
  return hash
end

function Storage:load(hash)
  log("load", hash)
  self.callbacks[hash] = makeCallback()
  self.write("wants", {hash})
  return assert(coroutine.yield())
end

function Storage:match(name, version)
  log("versions", name)
  self.waiting = coroutine.running()
  self.write("query", "MATCH " .. name .. ' ' .. (version or ""))
  return unpack(assert(coroutine.yield()))
end

function Storage:versions(name)
  log("versions", name)
  -- local results = {}
  -- self.fs.scandir(pathJoin("refs/tags", name), function (entry)
  --   if entry.type == "file" then
  --     results[#results + 1] = string.match(entry.name, "%d+%.%d+%.%d+[^/]*$")
  --   end
  -- end)
  -- return results
end

function Storage:read(tag)
  log("read", tag)
  -- local raw = self.fs.readFile(pathJoin("refs/tags/", tag))
  -- return raw and string.match(raw, "%x+")
end

function Storage:write(tag, hash)
  log("write", tag)
  -- local path = pathJoin("refs/tags/", tag)
  -- local data = hash .. "\n"
  -- if self.fs.readFile(path) == data then return end
  -- log("write", tag)
  -- self.fs.mkdirp(pathJoin(path, ".."))
  -- return self.fs.writeFile(path, data)
end

function Storage:begin()
  log("transaction", "begin")
  -- TODO: Implement
end

function Storage:commit()
  log("transaction", "commit", "success")
  -- TODO: Implement
end

function Storage:rollback()
  log("transaction", "rollback", "failure")
  -- TODO: Implement
end

return function (host, port)
  return Storage:new(host, port)
end
