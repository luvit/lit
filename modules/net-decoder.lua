local binToHex = require('./bin-to-hex')

-- Binary Encoding
-- SEND - 1Mxxxxxx [Mxxxxxxx] data
--        (M) is more flag, x is variable length unsigned int
-- WANT - 01xxxxxx (groups of 20 bytes)
--        (xxxxxx is number of wants)
-- NOPE - 00110000 (20 raw byte hash) - a wanted hash isn't there
-- GIVE - 00110001 (20 byte one-use auth token) (20 raw byte hash) - I want to give you a hash and it's dependencies
-- GOT  - 00110010 (20 raw byte hash) - reply that give was completed recursivly
local function decoder(chunk)
  local head = string.byte(chunk, 1)

  -- SEND len* data
  if bit.band(head, 0x80) > 0 then
    local length = bit.band(head, 0x3f)
    local i = 2
    if bit.band(head, 0x40) > 0 then
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

  -- WANT hash*
  if bit.band(head, 0x40) > 0 then
    local count = bit.band(head, 0x3f)
    if #chunk < count * 20 + 1 then return nil end
    local wants = {}
    for i = 2, count * 20 + 1, 20 do
      wants[#wants + 1] = binToHex(string.sub(chunk, i, i + 19))
    end
    return {"wants", wants}, string.sub(chunk, count * 20 + 2)
  end

  -- NOPE hash
  if head == 0x30 then
    if #chunk < 21 then return end
    return {"nope",
      binToHex(string.sub(chunk, 2, 21)),
    }, string.sub(chunk, 22)
  end

  -- GIVE hash
  if head == 0x31 then
    if #chunk < 41 then return end
    return {"give", {
      token = binToHex(string.sub(chunk, 2, 21)),
      hash = binToHex(string.sub(chunk, 22, 41)),
    }}, string.sub(chunk, 42)
  end

  -- GOT hash
  if head == 0x32 then
    if #chunk < 21 then return end
    return {"got",
      binToHex(string.sub(chunk, 2, 21)),
    }, string.sub(chunk, 22)
  end

  error("Unknown data")
end

assert(decoder(string.char(128 + 12) .. "Hello World") == nil)
assert(decoder(string.char(128 + 12) .. "Hello World\n")[2] == "Hello World\n")
assert(({decoder(string.char(128 + 12) .. "Hello World\nwith extra")})[2] == "with extra")
assert(#(decoder(string.char(128 + 64 + 7, 104) .. string.rep("0123456789", 100) .. "XX")[2]) == 1000)
assert(decoder(string.char(128 + 64, 128 + 78, 16) .. string.rep("0123456789", 500)) == nil)
assert(#(decoder(string.char(128 + 64, 128 + 78, 16) .. string.rep("0123456789", 1000) .. "XX")[2]) == 10000)

local e, x = decoder('BzBSXc$u\189y\193V\239\t\153!\145\239\187{\184\130|\180Pu\190C\129\172\209\199\159!l\245\184`Hwuxx')
assert(x == "xx")
assert(e[1] == "wants")
assert(#e[2] == 2)

e, x = decoder('1\130|\180Pu\190C\129\172\209\199\159!l\245\184`Hwu\130|\180Pu\190C\129\172\209\199\159!l\245\184`Hwuxx')
assert(x == 'xx')
assert(e[1] == 'give')
assert(#e == 2)
assert(e[2].token)
assert(e[2].hash)

e, x = decoder('0\130|\180Pu\190C\129\172\209\199\159!l\245\184`Hwuxx')
assert(x == 'xx')
assert(e[1] == 'nope')
assert(e[2] == '827cb45075be4381acd1c79f216cf5b860487775')
p(e)
assert(#e == 2)

return decoder
