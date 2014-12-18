local binToHex = require('creationix/hex-bin').binToHex

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
  -- WANT - 10xxxxxx (groups of 20 bytes)
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
      if bit.band(head, 0x40) == 0 then
        -- Make sure we have all the wants buffered before moving on.
        local size = (bit.band(head, 0x3f) + 1) * 20 + 1
        if #chunk < size then return nil end
        local wants = {}
        for i = 2, size, 20 do
          wants[#wants + 1] = binToHex(string.sub(chunk, i, i + 19))
        end
        return string.sub(chunk, size + 1), "wants", wants
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
    local term, tend = string.find(chunk, isServer and "\n" or "\n\n", 1, true)
    -- Make sure we have all data up to the terminator
    if not term then return end

    local line = string.sub(chunk, 1, term - 1)
    chunk = string.sub(chunk, tend + 1)
    line = string.gsub(line, "^%s+", "")
    line = string.gsub(line, "%s+$", "")

    if not isServer then
      return chunk, "reply", line
    end

    local command, query = string.match(line, "^(%u+) +(.*)")
    if not command then error("Invalid query") end
    return chunk, string.lower(command), query

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
           .. '\129[---20-byte-hash---]<== 20 byte hash ==>'
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
assert(t == "wants")
assert(#e == 2)
assert(e[1] == '5b2d2d2d32302d627974652d686173682d2d2d5d')
assert(e[2] == '3c3d3d20323020627974652068617368203d3d3e')
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
assert(t == "who")
assert(e == "are you?")
assert(input == 'XX')
assert(decode(input) == nil)

decode = decoder(false)
input = "LIT/0\n\nThere are those who call me Tim! \n\nxx\n"
input, t, e = decode(input)
assert(t == "agreement")
assert(e == 0)
input, t, e = decode(input)
assert(t == "reply")
assert(e == "There are those who call me Tim!")
assert(input == 'xx\n')
assert(decode(input) == nil)

return decoder
