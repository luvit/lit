local binToHex = require('hex-bin').binToHex
local hexToBin = require('hex-bin').hexToBin
local deflate = require('miniz').deflate
local inflate = require('miniz').inflate

local byte = string.byte
local sub = string.sub

-- ERROR - '\0' error
-- MESSAGE - COMMAND data
local function decodeText(message)
  if byte(message, 1) == 0 then
    return "error", sub(message, 2)
  end
  local name, data = string.match(message, "^([^ ]+) *(.*)$")
  assert(name, "Invalid message")
  return name, #data > 0 and data or nil
end
exports.decodeText = decodeText

-- WANTS - 0x00 len (20 bytes) * len
-- SEND - raw deflated data
local function decodeBinary(message)
  if #message >= 2 and byte(message, 1) == 0 then
    local wants = {}
    for i = 1, byte(message, 2) do
      local start = i * 20 - 17
      wants[i] = binToHex(sub(message, start, start + 19))
    end
    return "wants", wants
  end
  return "send", inflate(message, 1)
end
exports.decodeBinary = decodeBinary

local encoders = {}
exports.encoders = encoders

-- WANTS -  0x00 len (20 bytes) * len
function encoders.wants(hashes)
  assert(#hashes > 0, "Can't sent empty wants list")
  local data = {}
  for i = 1, #hashes do
    data[i] = hexToBin(hashes[i])
  end
  return {
    opcode = 2,
    payload = string.char(0, #hashes) .. table.concat(data),
  }
end

-- SEND - raw deflated data
function encoders.send(data)
  -- TDEFL_WRITE_ZLIB_HEADER             = 0x01000,
  -- 4095=Huffman+LZ (slowest/best compression)
  return {
    opcode = 2,
    payload = deflate(data, 0x01000 + 4095)
  }
end

-- ERROR - '\0' error
function encoders.error(message)
  return {
    opcode = 1,
    payload = "\0" .. message
  }
end

-- MESSAGE - COMMAND data
local function encode(name, data)
  local encoder = encoders[name]
  if encoder then return encoder(data) end
  local payload = data and (name .. ' ' .. data) or name
  return {
    opcode = 1,
    payload = payload
  }
end

function exports.makeRemote(webRead, webWrite, isClient)

  -- read
  local function innerRead()
    while true do
      local frame = webRead()
      -- p("INPUT", frame)
      if not frame then return end
      assert(isClient or frame.mask, "all frames sent by client must be masked")
      if frame.opcode == 1 then
        return decodeText(frame.payload)
      elseif frame.opcode == 2 then
        return decodeBinary(frame.payload)
      end
    end
  end

  local function read()
    local name, data = innerRead()
    -- p("network read", name, data and (#data <= 60 and data or # data))
    return name, data
  end

  local function readAs(expectedName)
    local name, data = read()
    if name == "error" then return nil, data end
    assert(expectedName == name, "Expected " .. expectedName .. ", but found " .. tostring(name))
    return data
  end

  local function writeAs(name, data)
    -- p("network write", name, data and (#data <= 60 and data or #data))
    if not name then return webWrite() end
    local frame = encode(name, data)
    frame.mask = isClient
    -- p("OUTPUT", frame)
    return webWrite(frame)
  end

  return {
    read = read,
    readAs = readAs,
    writeAs = writeAs,
  }
end
