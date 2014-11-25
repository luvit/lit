
local function charToBin(cc)
  return string.char(tonumber(cc, 16))
end

local function hexToBin(hex)
  return string.gsub(hex, "..", charToBin)
end

local function binToChar(c)
  return string.format("%02x", string.byte(c, 1))
end

local function binToHex(bin)
  return string.gsub(bin, ".", binToChar)
end


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
      "SEND", string.sub(chunk, i, i + length - 1)
    }, string.sub(chunk, i + length)
  end

  -- WANT hash*
  if bit.band(head, 0x40) > 0 then
    local count = bit.band(head, 0x3f)
    if #chunk < count * 20 + 1 then return nil end
    local wants = {"WANT"}
    for i = 2, count * 20 + 1, 20 do
      wants[#wants + 1] = binToHex(string.sub(chunk, i, i + 19))
    end
    return wants, string.sub(chunk, count * 20 + 2)
  end

  -- NOPE hash
  if head == 0x30 then
    if #chunk < 21 then return end
    return {"NOPE",
      binToHex(string.sub(2, 21)),
    }, string.sub(chunk, 22)
  end

  -- GIVE hash
  if head == 0x31 then
    if #chunk < 41 then return end
    return {"GIVE",
      binToHex(string.sub(2, 21)),
      binToHex(string.sub(22, 41)),
    }, string.sub(chunk, 42)
  end

  -- GOT hash
  if head == 0x32 then
    if #chunk < 21 then return end
    return {"GOT",
      binToHex(string.sub(2, 21)),
    }, string.sub(chunk, 22)
  end

  error("Unknown data")

end

local function encodeSend(data)
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

local function encodeWant(wants)
  assert(#wants < 64)
  local parts = {}
  for i = 1, #wants do
    parts[i] = hexToBin(wants[i])
  end
  return string.char(0x40 + #wants) .. table.concat(parts)
end

local function encodeNope(hash)
  assert(#hash == 40)
  return "0" .. hexToBin(hash)
end

local function encodeGive(token, hash)
  assert(#token == 40)
  assert(#hash == 40)
  return "1" .. hexToBin(token) .. hexToBin(hash)
end

local function encodeGot(hash)
  assert(#hash == 40)
  return "2" .. hexToBin(hash)
end

assert(decoder(string.char(128 + 12) .. "Hello World") == nil)
assert(decoder(string.char(128 + 12) .. "Hello World\n")[2] == "Hello World\n")
assert(({decoder(string.char(128 + 12) .. "Hello World\nwith extra")})[2] == "with extra")
assert(#(decoder(string.char(128 + 64 + 7, 104) .. string.rep("0123456789", 100) .. "XX")[2]) == 1000)
assert(decoder(string.char(128 + 64, 128 + 78, 16) .. string.rep("0123456789", 500)) == nil)
assert(#(decoder(string.char(128 + 64, 128 + 78, 16) .. string.rep("0123456789", 1000) .. "XX")[2]) == 10000)

p(decoder(string.char(64) .. "xx"))
p(decoder(string.char(64 + 1) ..
  hexToBin("7a425358632475bd79c156ef09992191efbb7bb8") .. "xx"))
p(decoder(string.char(64 + 2) ..
  hexToBin("7a425358632475bd79c156ef09992191efbb7bb8") ..
  hexToBin("827cb45075be4381acd1c79f216cf5b860487775") .. "xx"))

p(encodeWant({
  "7a425358632475bd79c156ef09992191efbb7bb8",
  "827cb45075be4381acd1c79f216cf5b860487775",
  "827cb45075be4381acd1c79f216cf5b860487775",
}))

p(encodeNope("827cb45075be4381acd1c79f216cf5b860487775"))

p(encodeGive("827cb45075be4381acd1c79f216cf5b860487775", "827cb45075be4381acd1c79f216cf5b860487775"))

p(encodeGot("827cb45075be4381acd1c79f216cf5b860487775"))

p(encodeSend("Hello World\n"))

-- local uv = require('uv')
-- local fs = require('./fs')

-- local server = uv.new_tcp()
-- uv.tcp_bind(server, "0.0.0.0", 4821)
-- uv.listen(server, 128, coroutine.wrap(function (err)
--   assert(not err, err)
--   local client = uv.new_tcp()
--   uv.accept(server, client)
--   p(client)
-- end))
