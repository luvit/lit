local binToHex = require('creationix/hex-bin').binToHex
local JSON = require('json')

local function decoder(isServer)
  local mode, handshakeDecode, agreementDecode, bodyDecode

  -- "LIT/" versions "\n" - Client handshake
  --        (versions) is comma separated list of protocol versions
  function handshakeDecode(chunk)
    local term = string.find(chunk, "\n", 1, true)
    if not term then
      if #chunk > 100 then error("handshake too long") end
      return
    end
    local line = string.sub(chunk, 1, term - 1)
    chunk = string.sub(chunk, term + 1)

    local list = string.match(line, "^LIT/(.*)$")
    if not list then
      error("Invalid lit handshake")
    end
    local versions = {}
    for v in string.gmatch(list, "[^,]+") do
      versions[tonumber(v)] = true
    end
    mode = bodyDecode
    return chunk, "handshake", versions
  end

  -- "LIT/" version  "\n" - Server agreement
  function agreementDecode(chunk)
    local term = string.find(chunk, "\n", 1, true)
    if not term then
      if #chunk > 100 then error("agreement too long") end
      return
    end
    local line = string.sub(chunk, 1, term - 1)
    chunk = string.sub(chunk, term + 1)

    local version = string.match(line, "^LIT/(.*)$")
    if not version then
      error("Invalid lit agreement")
    end
    mode = bodyDecode
    return chunk, "agreement", tonumber(version)
  end

  -- Binary Encoding
  -- WANT - 0x80 20 byte raw hash
  -- SEND - 11Mxxxxx [Mxxxxxxx] data
  --        (M) is more flag, x is variable length unsigned int
  -- Text Encoding
  -- QUERY - COMMAND data '\n' - sent by client to server
  -- REPLY - reply "\n\n" - sent by server to client
  function bodyDecode(chunk)
    local head = string.byte(chunk, 1)

    -- Binary frame when high bit is set
    if bit.band(head, 0x80) > 0 then

      -- WANT - 10xxxxxx (groups of 20 bytes)
      if head == 0x80 then
        -- Wait for the full hash
        if #chunk < 21 then return nil end
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
      return string.sub(chunk, i + length), "send", string.sub(chunk, i, i + length - 1)

    end

    -- Text frame with \n or \n\n terminator
    local term = string.find(chunk, "\n", 1, true)
    -- Make sure we have all data up to the terminator
    if not term then return end

    local line = string.sub(chunk, 1, term - 1)
    chunk = string.sub(chunk, term + 1)

    if head == 0 then
      return chunk, "error", string.sub(line, 2)
    end

    if not isServer then
      local data, _, err = JSON.parse(line)
      assert(not err, err)
      return chunk, "reply", data
    end

    -- Trim whitespace on both ends
    line = string.gsub(line, "^%s+", "")
    line = string.gsub(line, "%s+$", "")

    local command, query = string.match(line, "^(%u+) +(.*)")
    if not command then error("Invalid query") end
    return chunk, command, query

  end

  mode = isServer and handshakeDecode or agreementDecode
  return function (chunk)
    return mode(chunk)
  end
end

local large = string.rep("0123456789", 100)
local huge = string.rep("0123456789", 1000)

-- Sanity test server side
local input = "LIT/0,1\n"
           .. string.char(128 + 64 + 12) .. "Hello World\n"
           .. string.char(128 + 64 + 32 + 7, 104) .. large
           .. string.char(128 + 64 + 32, 128 + 78, 16) .. huge
           .. '\128[---20-byte-hash---]'
           .. "XX"
local decode = decoder(true)
local t, e
input, t, e = decode(input)
assert(t == "handshake")
assert(e[0])
assert(e[1])
input, t, e = decode(input)
assert(t == "send" and e == "Hello World\n")
input, t, e = decode(input)
assert(t == "send" and e == large)
input, t, e = decode(input)
assert(t == "send" and e == huge)
input, t, e = decode(input)
assert(t == "want")
assert(e == '5b2d2d2d32302d627974652d686173682d2d2d5d')
assert(input == "XX")
assert(decode(input) == nil)

-- Sanity tests for decoding ASCII frames
decode = decoder(true)
input = "LIT/0\n WHO are you? \nXX"
input, t, e = decode(input)
assert(t == "handshake")
assert(e[0])
assert(not e[1])
input, t, e = decode(input)
assert(t == "WHO")
assert(e == "are you?")
assert(input == 'XX')
assert(decode(input) == nil)

decode = decoder(false)
input = 'LIT/0\n"There are those who call me Tim!"\n[true,false]\n42\nxx'
input, t, e = decode(input)
assert(t == "agreement")
assert(e == 0)
input, t, e = decode(input)
assert(t == "reply")
assert(e == "There are those who call me Tim!")
input, t, e = decode(input)
assert(t == "reply")
assert(#e == 2)
assert(e[1] == true)
assert(e[2] == false)
input, t, e = decode(input)
assert(t == "reply")
assert(e == 42)
assert(input == 'xx')
p(decode(input))
assert(decode(input) == nil)

return decoder
