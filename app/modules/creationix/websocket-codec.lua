exports.name = "creationix/websocket-codec"
exports.version = "0.1.0"

local digest = require('openssl').digest.digest
local base64 = require('openssl').base64
local random = require('openssl').random
local hexToBin = require('creationix/hex-bin').hexToBin

local function applyMask(data, mask)
  local bytes = {
    [0] = string.byte(mask, 1),
    [1] = string.byte(mask, 2),
    [2] = string.byte(mask, 3),
    [3] = string.byte(mask, 4)
  }
  local out = {}
  for i = 1, #data do
    out[i] = string.char(
      bit.bxor(string.byte(data, i), bytes[(i - 1) % 4])
    )
  end
  return table.concat(out)
end

function exports.decode(chunk)
  if #chunk < 2 then return end
  local second = string.byte(chunk, 2)
  local len = bit.band(second, 0x7f)
  local offset
  if len == 126 then
    if #chunk < 4 then return end
    len = bit.bor(
      bit.lshift(string.byte(chunk, 3), 8),
      string.byte(chunk, 4))
    offset = 4
  elseif len == 127 then
    if #chunk < 10 then return end
    len = bit.bor(
      bit.lshift(string.byte(chunk, 3), 56),
      bit.lshift(string.byte(chunk, 4), 48),
      bit.lshift(string.byte(chunk, 5), 40),
      bit.lshift(string.byte(chunk, 6), 32),
      bit.lshift(string.byte(chunk, 7), 24),
      bit.lshift(string.byte(chunk, 8), 16),
      bit.lshift(string.byte(chunk, 9), 8),
      string.byte(chunk, 10))
    offset = 10
  else
    offset = 2
  end
  local mask = bit.band(second, 0x80) > 0
  if mask then
    offset = offset + 4
  end
  if #chunk < offset + len - 1 then return end

  local first = string.byte(chunk, 1)
  local payload = string.sub(chunk, offset + 1, offset + len)
  if mask then
    payload = applyMask(payload, string.sub(chunk, offset - 3, offset))
  end
  local extra = string.sub(chunk, offset + len + 1)
  return {
    fin = bit.band(first, 0x80) > 0,
    rsv1 = bit.band(first, 0x40) > 0,
    rsv2 = bit.band(first, 0x20) > 0,
    rsv3 = bit.band(first, 0x10) > 0,
    opcode = bit.band(first, 0xf),
    mask = mask,
    len = len,
    payload = payload
  }, extra
end

function exports.encode(item)
  if type(item) == "string" then
    item = {
      opcode = 2,
      payload = item
    }
  end
  local payload = item.payload
  assert(type(payload) == "string", "payload must be string")
  local len = #payload
  local chars = {
    string.char(bit.bor(0x80, item.opcode or 2)),
    string.char(bit.bor(item.mask and 0x80 or 0,
      len < 0x10 and len or len < 0x10000 and 126 or 127))
  }
  if len >= 0x10000 then
    chars[3] = string.char(bit.band(bit.rshift(len, 56), 0xff))
    chars[4] = string.char(bit.band(bit.rshift(len, 48), 0xff))
    chars[5] = string.char(bit.band(bit.rshift(len, 40), 0xff))
    chars[6] = string.char(bit.band(bit.rshift(len, 32), 0xff))
    chars[7] = string.char(bit.band(bit.rshift(len, 24), 0xff))
    chars[8] = string.char(bit.band(bit.rshift(len, 16), 0xff))
    chars[9] = string.char(bit.band(bit.rshift(len, 8), 0xff))
    chars[10] = string.char(bit.band(len, 0xff))
  elseif len >= 0x10 then
    chars[3] = string.char(bit.band(bit.rshift(len, 8), 0xff))
    chars[4] = string.char(bit.band(len, 0xff))
  end
  if item.mask then
    local mask = random(4)
    return table.concat(chars) .. mask .. applyMask(payload, mask)
  end
  return table.concat(chars) .. payload
end

local websocketGuid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
function exports.handshake(head, protocol)

  -- Websocket connections must be GET requests
  if not head.method == "GET" then return end

  -- Parse the headers for quick reading
  local headers = {}
  for i = 1, #head do
    local name, value = unpack(head[i])
    headers[name:lower()] = value
  end

  -- Must have 'Upgrade: websocket' and 'Connection: Upgrade' headers
  if not (headers.upgrade and headers.connection
      and headers.upgrade:lower() == "websocket"
      and headers.connection:lower() == "upgrade"
  ) then return end

  -- Make sure it's a new client speaking v13 of the protocol
  if tonumber(headers["sec-websocket-version"]) < 13 then
    return nil, "only websocket protocol v13 supported"
  end

  local key = headers["sec-websocket-key"]
  if not key then
    return nil, "websocket security key missing"
  end

  -- If the server wants a specified protocol, check for it.
  if protocol then
    local foundProtocol = false
    local list = headers["sec-websocket-protocol"]
    if list then
      for item in string.gmatch(list, "[^, ]+") do
        if item == protocol then
          foundProtocol = true
          break
        end
      end
    end
    if not foundProtocol then
      return nil, "specified protocol missing in request"
    end
  end

  local accept = base64(hexToBin(digest("sha1", key .. websocketGuid))):gsub("\n", "")

  local res = {
    code = 101,
    {"Upgrade", "websocket"},
    {"Connection", "Upgrade"},
    {"Sec-WebSocket-Accept", accept},
  }
  if protocol then
    res[#res + 1] = {"Sec-WebSocket-Protocol", protocol}
  end

  return res
end
