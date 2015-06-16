
exports.name = "creationix/coro-tcp"
exports.version = "1.0.6"
exports.dependencies = {
  "creationix/coro-channel@1.1.0"
}
exports.homepage = "https://github.com/luvit/lit/blob/master/deps/coro-tcp.lua"
exports.description = "An coro style tcp client and server helper."
exports.tags = {"coro", "tcp"}
exports.license = "MIT"
exports.author = { name = "Tim Caswell" }

local uv = require('uv')
local wrapStream = require('coro-channel').wrapStream

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
  assert(server:listen(256, function (err)
    assert(not err, err)
    local socket = uv.new_tcp()
    server:accept(socket)
    coroutine.wrap(function ()
      local success, failure = xpcall(function ()
        local read, write = wrapStream(socket)
        return onConnect(read, write, socket)
      end, debug.traceback)
      if not success then
        print(failure)
      end
      if not socket:is_closing() then
        socket:close()
      end
    end)()
  end))
end
