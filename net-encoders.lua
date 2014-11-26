local hexToBin = require('./hex-to-bin')

-- Binary Encoding
-- SEND - 1Mxxxxxx [Mxxxxxxx] data
--        (M) is more flag, x is variable length unsigned int
-- WANT - 01xxxxxx (groups of 20 bytes)
--        (xxxxxx is number of wants)
-- NOPE - 00110000 (20 raw byte hash) - a wanted hash isn't there
-- GIVE - 00110001 (20 byte one-use auth token) (20 raw byte hash) - I want to give you a hash and it's dependencies
-- GOT  - 00110010 (20 raw byte hash) - reply that give was completed recursivly
local encoders = exports

function encoders.send(data)
  local length = #data
  local head = ""
  local more = 0
  while length >= 64 do
    local n = length % 128
    head = string.char(more + n) .. head
    more = 0x80
    length = (length - n) / 128
  end
  if more > 0 then more = 0x40 end
  head = string.char(0x80 + more + length) .. head
  return head .. data
end

function encoders.wants(wants)
  assert(type(wants) == "table")
  assert(#wants < 64)
  local parts = {}
  for i = 1, #wants do
    parts[i] = hexToBin(wants[i])
  end
  return string.char(0x40 + #wants) .. table.concat(parts)
end

function encoders.nope(hash)
  assert(#hash == 40)
  return "0" .. hexToBin(hash)
end

function encoders.give(give)
  assert(type(give) == "table")
  assert(type(give.token) == "string")
  assert(type(give.hash) == "string")
  assert(#give.token == 40)
  assert(#give.hash == 40)
  return "1" .. hexToBin(give.token) .. hexToBin(give.hash)
end

function encoders.got(hash)
  assert(#hash == 40)
  return "2" .. hexToBin(hash)
end

-- Inline unit tests for sanity
assert(encoders.send("Hello") == '\133Hello')
assert(encoders.send(string.rep("1234", 100)) == '\195\016' .. string.rep("1234", 100))
assert(encoders.send(string.rep("1234", 10000)) == '\194\184\064' .. string.rep("1234", 10000))
assert(encoders.wants({"7a425358632475bd79c156ef09992191efbb7bb8"}) == 'AzBSXc$u\189y\193V\239\t\153!\145\239\187{\184')
assert(encoders.wants({
  "7a425358632475bd79c156ef09992191efbb7bb8",
  "827cb45075be4381acd1c79f216cf5b860487775",
}) == 'BzBSXc$u\189y\193V\239\t\153!\145\239\187{\184\130|\180Pu\190C\129\172\209\199\159!l\245\184`Hwu')
assert(encoders.nope("827cb45075be4381acd1c79f216cf5b860487775") == '0\130|\180Pu\190C\129\172\209\199\159!l\245\184`Hwu')
assert(encoders.give({
  token = "827cb45075be4381acd1c79f216cf5b860487775",
  hash = "827cb45075be4381acd1c79f216cf5b860487775"
}) == '1\130|\180Pu\190C\129\172\209\199\159!l\245\184`Hwu\130|\180Pu\190C\129\172\209\199\159!l\245\184`Hwu')
assert(encoders.got("827cb45075be4381acd1c79f216cf5b860487775") == '2\130|\180Pu\190C\129\172\209\199\159!l\245\184`Hwu')
