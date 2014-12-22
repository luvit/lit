local uv = require('uv')
local digest = require('openssl').digest.digest
local codec = require('./codec')

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

return function (storage, host, port)
  local socket, err = connect(host, port or 4821)
  if not socket then return nil, err end

  local read, write = codec(false, socket)

  local callbacks = {}
  local waiting

  -- Handshake with the remote server
  write("handshake", {0})
  local command, data = read()
  -- Make sure the server is speaking protocol v0
  assert(command == "agreement" and data == 0)

  coroutine.wrap(xpcall)(function ()
    for command, data in read do
      if command == "reply" and waiting then
        local thread = waiting
        waiting = nil
        assert(coroutine.resume(thread, data))
      elseif command == "error" and waiting then
        local thread = waiting
        waiting = nil
        assert(coroutine.resume(thread, nil, data))
      elseif command == "want" then
        write("send", storage.load(data))
      elseif command == "send" then
        local hash = digest("sha1", data)
        local callback = callbacks[hash]
        assert(callback, "Unexpected value sent!")
        callbacks[hash] = nil
        callback(nil, data)
      else
        p(command, data)
      end
    end
  end, function (message)
    error(debug.traceback(message))
  end)

  local upstream = {}

  function upstream.send(value)
  end

  function upstream.want(hash)
    callbacks[hash] = makeCallback()
    write("want", hash)
    return assert(coroutine.yield())
  end

  function upstream.query(command, ...)
    waiting = coroutine.running()
    write("query", command .. ' ' .. table.concat({...}, ' '))
    return coroutine.yield()
  end

  function upstream.close()
    return socket:close()
  end

  return upstream

end




-- function Storage:load(hash)
-- end

-- function Storage:match(name, version)
--   log("versions", name)
--   self.waiting = coroutine.running()
--   self.write("query", "MATCH " .. name .. ' ' .. (version or ""))
--   return unpack(assert(coroutine.yield()))
-- end

-- function Storage:versions(name)
--   log("versions", name)
--   -- local results = {}
--   -- self.fs.scandir(pathJoin("refs/tags", name), function (entry)
--   --   if entry.type == "file" then
--   --     results[#results + 1] = string.match(entry.name, "%d+%.%d+%.%d+[^/]*$")
--   --   end
--   -- end)
--   -- return results
-- end

-- function Storage:read(tag)
--   log("read", tag)
--   -- local raw = self.fs.readFile(pathJoin("refs/tags/", tag))
--   -- return raw and string.match(raw, "%x+")
-- end

-- function Storage:write(tag, hash)
--   log("write", tag)
--   -- local path = pathJoin("refs/tags/", tag)
--   -- local data = hash .. "\n"
--   -- if self.fs.readFile(path) == data then return end
--   -- log("write", tag)
--   -- self.fs.mkdirp(pathJoin(path, ".."))
--   -- return self.fs.writeFile(path, data)
-- end

-- function Storage:begin()
--   log("transaction", "begin")
--   -- TODO: Implement
-- end

-- function Storage:commit()
--   log("transaction", "commit", "success")
--   -- TODO: Implement
-- end

-- function Storage:rollback()
--   log("transaction", "rollback", "failure")
--   -- TODO: Implement
-- end

-- return function (host, port)
--   return Storage:new(host, port)
-- end
-- ]]
