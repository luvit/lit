exports.name = "creationix/coro-channel"
exports.version = "1.3.0"
exports.homepage = "https://github.com/luvit/lit/blob/master/deps/coro-channel.lua"
exports.description = "An adapter for wrapping uv streams as coro-streams and chaining filters."
exports.tags = {"coro", "adapter"}
exports.license = "MIT"
exports.author = { name = "Tim Caswell" }

local function wrapRead(socket, decode)
  local paused = true

  local queue = {}
  local tindex = 0
  local dindex = 0

  local function dispatch(data)
    if tindex > dindex then
      local thread = queue[dindex]
      queue[dindex] = nil
      dindex = dindex + 1
      assert(coroutine.resume(thread, unpack(data)))
    else
      queue[dindex] = data
      dindex = dindex + 1
      if not paused then
        paused = true
        assert(socket:read_stop())
      end
    end
  end

  local buffer = ""
  local function onRead(err, chunk)
    if not decode or not chunk or err then
      return dispatch(err and {nil, err} or {chunk})
    end
    buffer = buffer .. chunk
    while true do
      local item, extra = decode(buffer)
      if not extra then return end
      buffer = extra
      dispatch({item})
    end
  end

  return function ()
    if dindex > tindex then
      local data = queue[tindex]
      queue[tindex] = nil
      tindex = tindex + 1
      return unpack(data)
    end
    if paused then
      paused = false
      assert(socket:read_start(onRead))
    end
    queue[tindex] = coroutine.running()
    tindex = tindex + 1
    return coroutine.yield()
  end,
  function (newDecode)
    decode = newDecode
  end

end

local function wrapWrite(socket, encode)

  local function wait()
    local thread = coroutine.running()
    return function (err)
      assert(coroutine.resume(thread, err))
    end
  end

  local function shutdown()
    socket:shutdown(wait())
    coroutine.yield()
    if not socket:is_closing() then
      socket:close()
    end
  end

  return function (chunk)
    if chunk == nil then
      return shutdown()
    end
    if encode then
      chunk = encode(chunk)
    end
    assert(socket:write(chunk, wait()))
    local err = coroutine.yield()
    return not err, err
  end,
  function (newEncode)
    encode = newEncode
  end

end

exports.wrapRead = wrapRead
exports.wrapWrite = wrapWrite

-- Given a raw uv_stream_t userdata, return coro-friendly read/write functions.
function exports.wrapStream(socket, encode, decode)
  return wrapRead(socket, encode), wrapWrite(socket, decode)
end


function exports.chain(...)
  local args = {...}
  local nargs = select("#", ...)
  return function (read, write)
    local threads = {} -- coroutine thread for each item
    local waiting = {} -- flag when waiting to pull from upstream
    local boxes = {}   -- storage when waiting to write to downstream
    for i = 1, nargs do
      threads[i] = coroutine.create(args[i])
      waiting[i] = false
      local r, w
      if i == 1 then
        r = read
      else
        function r()
          local j = i - 1
          if boxes[j] then
            local data = boxes[j]
            boxes[j] = nil
            assert(coroutine.resume(threads[j]))
            return unpack(data)
          else
            waiting[i] = true
            return coroutine.yield()
          end
        end
      end
      if i == nargs then
        w = write
      else
        function w(...)
          local j = i + 1
          if waiting[j] then
            waiting[j] = false
            assert(coroutine.resume(threads[j], ...))
          else
            boxes[i] = {...}
            coroutine.yield()
          end
        end
      end
      assert(coroutine.resume(threads[i], r, w))
    end
  end
end
