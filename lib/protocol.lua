local binToHex = require('creationix/hex-bin').binToHex
local hexToBin = require('creationix/hex-bin').hexToBin

-- Binary Encoding
-- WANT - 0x80 20 byte raw hash
-- SEND - 11Mxxxxx [Mxxxxxxx] data
--        (M) is more flag, x is variable length unsigned int
-- Text Encoding
-- MESSAGE - COMMAND data '\n' - sent by client to server
-- ERROR - '\0' error '\n'
local function decode(chunk)
  local head = string.byte(chunk, 1)

  -- Binary frame when high bit is set
  if bit.band(head, 0x80) > 0 then

    -- WANT - 10xxxxxx (groups of 20 bytes)
    if head == 0x80 then
      -- Wait for the full hash
      if #chunk < 21 then return end
      return string.sub(chunk, 22), "want", binToHex(string.sub(chunk, 2, 21))
    end

    -- SEND - 11Mxxxxx [Mxxxxxxx] data
    local length = bit.band(head, 0x1f)
    local i = 2
    if bit.band(head, 0x20) > 0 then
      repeat
        if i > #chunk then return end
        head = string.byte(chunk, i)
        i = i + 1
        length = bit.bor(bit.lshift(length, 7), bit.band(head, 0x7f))
      until bit.band(head, 0x80) == 0
    end
    if #chunk < i + length - 1 then return end
    local body = string.sub(chunk, i, i + length - 1)
    return string.sub(chunk, i + length), "send", body

  end

  -- Text frame with \n terminator
  local term = string.find(chunk, "\n", 1, true)
  -- Make sure we have all data up to the terminator
  if not term then return end

  local line = string.sub(chunk, 1, term - 1)
  chunk = string.sub(chunk, term + 1)

  -- Parse out errors
  if head == 0 then
    return chunk, "error", string.sub(line, 2)
  end

  local name, message = string.match(line, "^([^ /]+) *(.*)$")
  if not name then error("Invalid message") end

  -- Trim whitespace on both ends
  message = string.gsub(message, "^%s+", "")
  message = string.gsub(message, "%s+$", "")
  return chunk, name, message
end

local encoders = {}
function encoders.want(hash)
  return '\128' .. hexToBin(hash)
end

-- SEND - 11Mxxxxx [Mxxxxxxx] data
--        (M) is more flag, x is variable length unsigned int
function encoders.send(data)
  local length = #data
  local head = ""
  local more = 0
  while length >= 0x20 do
    local n = length % 0x80
    head = string.char(more + n) .. head
    more = 0x80
    length = (length - n) / 0x80
  end
  if more > 0 then more = 0x20 end
  head = string.char(0xc0 + more + length) .. head
  return head .. data
end

function encoders.message(name, message)
  return (message and (name .. message) or name) .. "\n"
end

-- Given blocking read and write functions, implement the lit network protocol.
-- The 'isServer' flag tells it which half of the handshake to speak.
return function (handler, socket)
  local buffer = ""

  local function onRead(err, chunk)
    if not chunk then
      if not socket:is_closing() then socket:close() end
      return handler.done(err)
    end
    buffer = buffer .. chunk
    while #buffer > 0 do
      local extra, name, data = decode(buffer)
      if extra then
        buffer = extra
        local fn = handler[name]
        assert(fn, "Missing handler for " .. name)
        fn(data)
      end
    end
  end

  socket:read_start(onRead)
end


--   local function readLine(limit, callback)
--     -- Read the first line
--     local term
--     repeat
--       if #buffer > limit then
--         error("Line too long")
--       end
--       local chunk = read()
--       buffer = buffer .. chunk
--       term = string.find(buffer, "\n", 1, true)
--     until term
--     local line = string.sub(buffer, 1, term - 1)
--     buffer = string.sub(buffer, term + 1)
--     return line
--   end

--   --
--   local threads = {}
--   local function waitFor(name)
--     local thread = coroutine.running()
--     threads[name] = thread
--     return coroutine.yield()
--   end

--   local callbacks = {}
--   local function on(name, callback)
--     callbacks[name] = callback
--   end

--   local function emit(name, value)
--     if name == "error" then error(value) end
--     local callback = callbacks[name]
--     if callback then
--       return callback(...)
--     end
--     local thread = threads[name]
--     if thread then
--       threads[name] = nil
--       return assert(coroutine.resume(thread, ...))
--     end
--     error("No handler for '" .. name .. "' event")
--   end

--   local function send(name, ...)
--     if not name then return write() end
--     local encoder = encoders[name]
--     if encoder then
--       return write(encoder(...))
--     end
--     return write(name .. ' ' .. table.concat({...}, "\0") .. '\n')
--   end

--   -- Handle the handshake
--   if isServer then
--     local versions = string.match(readLine(100), "^LIT/(.*)")
--     assert(versions, "Expected lit handshake")
--     local list = {}
--     for version in string.gmatch(versions, "[^,]+") do
--       list[version] = true
--     end
--     assert(list["0"], "Sorry, only version 0 supported")
--     write("LIT/0\n")
--   else
--     write("LIT/0\n")
--     local handshake = readLine(100)
--     assert(handshake == "LIT/0", "Expected lit handshake")
--   end

--   -- Create a new coroutine to handle incoming events
--   -- Call this after initializing your event handlers.
--   local function start(callback)
--     coroutine.wrap(xpcall)(function ()
--       while true do
--         while #buffer > 0 do
--           local success, extra, name, data = pcall(decode, buffer)
--           if not success then
--             emit("error", extra)
--             write()
--             return callback and callback(extra)
--           end
--           if not extra then break end
--           buffer = extra
--           emit(name, unpack(data))
--         end
--         local chunk = read()
--         if not chunk then break end
--         buffer = buffer .. chunk
--       end
--       write()
--       return callback and callback()
--     end, fail)
--   end

--   return {
--     start = start,
--     waitFor = waitFor,
--     on = on,
--     emit = emit,
--     send = send
--   }

-- end
