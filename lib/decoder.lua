local binToHex = require('creationix/hex-bin').binToHex

-- Binary Encoding
-- "LIT?" versions "\n\n" - Client handshake
--        (versions) is comma separated list of protocol versions
-- "LIT!" version  "\n\n" - Server response
-- WANT - 10xxxxxx (groups of 20 bytes)
-- SEND - 11Mxxxxx [Mxxxxxxx] data
--        (M) is more flag, x is variable length unsigned int
-- QUERY - "?" query "\n\n"
-- REPLY - "!" reply "\n\n"
local function decoder(chunk)
  local head = string.byte(chunk, 1)

  -- Binary frame when high bit is set
  if bit.band(head, 0x80) > 0 then

    -- WANT - 10xxxxxx (groups of 20 bytes)
    if bit.band(head, 0x40) == 0 then
      -- Make sure we have all the wants buffered before moving on.
      local size = (bit.band(head, 0x3f) + 1) * 20 + 1
      if #chunk < size then return nil end
      local wants = {}
      for i = 2, size, 20 do
        wants[#wants + 1] = binToHex(string.sub(chunk, i, i + 19))
      end
      return {"wants", wants}, string.sub(chunk, size + 1)
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
    return {
      "send", string.sub(chunk, i, i + length - 1)
    }, string.sub(chunk, i + length)

  end

  -- Text frame with \n\n terminator
  local term = string.find(chunk, "\n\n", 1, true)
  -- Make sure we have all data up to the terminator
  if not term then return end
  local line = string.sub(chunk, 1, term - 1)
  chunk = string.sub(chunk, term + 2)
  head = string.byte(line, 1)

  if head == 63 then -- '?'
    return {"query", string.sub(line, 2)}, chunk
  end
  if head == 33 then -- '!'
    return {"reply", string.sub(line, 2)}, chunk
  end

  if head == 76 then -- 'L'
    local form, version = string.match(line, "^LIT([%?%!])(.*)$")
    if form == "!" then
      return {"accept", version}, chunk
    end
    local versions = {}
    for v in string.gmatch(version, "[^,]+") do
      versions[#versions + 1] = v
    end
    return {"init", versions}, chunk
  end

  return line, chunk
end

-- Sanity tests for decoding of binary SEND frames
assert(decoder(string.char(128 + 64 + 12) .. "Hello World") == nil)
assert(decoder(string.char(128 + 64 + 12) .. "Hello World\n")[2] == "Hello World\n")
assert(({decoder(string.char(128 + 64 + 12) .. "Hello World\nwith extra")})[2] == "with extra")
assert(#(decoder(string.char(128 + 64 + 32 + 7, 104) .. string.rep("0123456789", 100) .. "XX")[2]) == 1000)
assert(decoder(string.char(128 + 64 + 32, 128 + 78, 16) .. string.rep("0123456789", 500)) == nil)
assert(#(decoder(string.char(128 + 64 + 32, 128 + 78, 16) .. string.rep("0123456789", 1000) .. "XX")[2]) == 10000)

-- Sanity tests for decoding of binary WANTS frames
local e, x = decoder('\129[---20-byte-hash---]<== 20 byte hash ==>xx')
assert(x == "xx")
assert(e[1] == "wants")
assert(#e[2] == 2)
assert(e[2][1] == '5b2d2d2d32302d627974652d686173682d2d2d5d')
assert(e[2][2] == '3c3d3d20323020627974652068617368203d3d3e')

-- Sanity tests for decoding ASCII frames
local input = "LIT?0,1\n\nLIT!0\n\n?Who are you?\n\n!There are those who call me Tim!\n\nthis is a line\nwith data\n\nand more data\nthat goes on for a while\n\nxx\n"
e, input = decoder(input)
assert(e[1] == "init")
assert(#e[2] == 2)
assert(e[2][1] == "0")
assert(e[2][2] == "1")
e, input = decoder(input)
assert(e[1] == "accept")
assert(e[2] == "0")
e, input = decoder(input)
assert(e[1] == "query")
assert(e[2] == "Who are you?")
e, input = decoder(input)
assert(e[1] == "reply")
assert(e[2] == "There are those who call me Tim!")
e, input = decoder(input)
assert(e == "this is a line\nwith data")
e, input = decoder(input)
assert(e == "and more data\nthat goes on for a while")
assert(input == 'xx\n')
assert(decoder(input) == nil)

return decoder

