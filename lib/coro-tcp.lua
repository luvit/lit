local uv = require('uv')
local wrapStream = require('creationix/coro-channel').wrapStream

local function makeCallback()
  local thread = coroutine.running()
  return function (err, data)
    if err then
      return assert(coroutine.resume(thread, nil, err))
    end
    return assert(coroutine.resume(thread, data or true))
  end
end
exports.makeCallback = makeCallback

function exports.connect(host, port)
  local res, success, err
  uv.getaddrinfo(host, port, { socktype = "stream", family="inet" }, makeCallback())
  res, err = coroutine.yield()
  if not res then return nil, err end
  local socket = uv.new_tcp()
  socket:connect(res[1].addr, res[1].port, makeCallback())
  success, err = coroutine.yield()
  if not success then return nil, err end
  local read, write = wrapStream(socket)
  return read, write, socket
end

function exports.createServer(addr, port, onConnect)
  local server = uv.new_tcp()
  assert(server:bind(addr, port))
  server:listen(256, function (err)
    assert(not err, err)
    local socket = uv.new_tcp()
    server:accept(socket)
    coroutine.wrap(xpcall)(function ()
      local read, write = wrapStream(socket)
      return onConnect(read, write, socket)
    end, function (failure)
      print(debug.stacktrace(failure))
      socket:close()
    end)
  end)
end
