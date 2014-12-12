local binToHex = require('./bin-to-hex')

-- Binary Encoding
-- SEND - 1Mxxxxxx [Mxxxxxxx] data
--        (M) is more flag, x is variable length unsigned int
-- WANT - 01xxxxxx (groups of 20 bytes)
--        (xxxxxx is number of wants)
-- NOPE - 00110000 (20 raw byte hash) - a wanted hash isn't there
-- GOT  - 00110001 (20 raw byte hash) - reply that a tag was completed recursivly

-- QUERY - 00110010 cstring - username/packagename
-- REPLY - 00110011 (20 raw byte hash) - hash to tree containing response
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

  -- GOT hash
  if head == 0x31 then
    if #chunk < 21 then return end
    return {"got",
      binToHex(string.sub(chunk, 2, 21)),
    }, string.sub(chunk, 22)
  end

  -- QUERY user/package
  if head == 0x32 then

    local n = string.find(chunk, "\0")
    if not n then
      if #chunk < 4096 then return end
      error("query too long")
    end
    return {"query",
      string.sub(chunk, 2, n - 1)
    }, string.sub(chunk, n + 1)
  end

  -- REPLY hash
  if head == 0x33 then
    if #chunk < 21 then return end
    return {"reply",
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

e, x = decoder('0\130|\180Pu\190C\129\172\209\199\159!l\245\184`Hwuxx')
assert(x == 'xx')
assert(e[1] == 'nope')
assert(e[2] == '827cb45075be4381acd1c79f216cf5b860487775')
assert(#e == 2)

e, x = decoder('1\130|\180Pu\190C\129\172\209\199\159!l\245\184`Hwuxx')
assert(x == 'xx')
assert(e[1] == 'got')
assert(e[2] == '827cb45075be4381acd1c79f216cf5b860487775')
assert(#e == 2)

e, x = decoder('2creationix/greeting\000xx')
assert(x == 'xx')
assert(e[1] == 'query')
assert(e[2] == 'creationix/greeting')
assert(#e == 2)

e, x = decoder('3\130|\180Pu\190C\129\172\209\199\159!l\245\184`Hwuxx')
assert(x == 'xx')
assert(e[1] == 'reply')
assert(e[2] == '827cb45075be4381acd1c79f216cf5b860487775')
assert(#e == 2)

return decoder

