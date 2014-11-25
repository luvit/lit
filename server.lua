local uv = require('uv')
local fs = require('./fs')

local server = uv.new_tcp()

-- Binary Encoding
-- SEND - 1Mxxxxxx [Mxxxxxxx] data
--        (M) is more flag, x is variable length unsigned int
-- WANT - 01xxxxxx (groups of 20 bytes)
--        (xxxxxx is number of wants)
-- NOPE - 00110000 (20 raw byte hash) - a wanted hash isn't there
-- GIVE - 00110001 (20 byte one-use auth token) (20 raw byte hash) - I want to give you a hash and it's dependencies
-- GOT  - 00110010 (20 raw byte hash) - reply that give was completed recursivly
local function decoder(read)
  while true do
    local char = read(1)
    local head = string.byte(char, 1)
    if bit.band(head, 0x80) > 0 then
      -- SEND len* data
      local length = bit.band(head, 0x3f)
      if bit.band(head, 0x40) > 0 then
        repeat
          head = string.byte(read(1), 1)
          length = bit.bor(bit.lshift(length, 7), bit.band(head, 0x7f))
        until bit.band(head, 0x80) == 0
      end
      coroutine.yield("SEND", read(length))
    elseif bit.band(head, 0x40) > 0 then
      -- WANT hash*
      local wants = {}
      for i = 1, bit.band(head, 0x3f) do
        wants[i] = read(20)
      end
      coroutine.yield("WANT", wants)
    elseif char == "0" then
      -- NOPE hash
      coroutine.yield("NOPE", read(20))
    elseif char == "1" then
      -- GIVE token hash
      coroutine.yield("GIVE", read(20), read(20))
    elseif char == "2" then
      -- GOT hash
      coroutine.yield("GOT", read(20))
    else
      coroutine.yield("ERROR")
    end
  end
end

uv.tcp_bind(server, "0.0.0.0", 4821)
uv.listen(server, 128, coroutine.wrap(function (err)
  assert(not err, err)
  local client = uv.new_tcp()
  uv.accept(server, client)
  p(client)
end))
