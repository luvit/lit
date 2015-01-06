local binToHex = require('creationix/hex-bin').binToHex
local hexToBin = require('creationix/hex-bin').hexToBin
local deflate = require('miniz').deflate
local inflate = require('miniz').inflate

-- Binary Encoding
-- WANT - 0x80 20 byte raw hash
-- SEND - 11Mxxxxx [Mxxxxxxx] data
--        (M) is more flag, x is variable length unsigned int
-- Text Encoding
-- MESSAGE - COMMAND data '\n' - sent by client to server
-- ERROR - '\0' error '\n'
local function decode(chunk)
  local head = string.byte(chunk, 1)

  -- Binary frame when high bit is set
  if bit.band(head, 0x80) > 0 then

    -- WANT - 10xxxxxx (groups of 20 bytes)
    if bit.band(head, 0x40) == 0 then
      -- Wait for the full hash
      local num = bit.band(head, 0x3f) + 1
      if #chunk < 20 * num + 1 then return end
      local hashes = {}
      for i = 1, num do
        local start = 2 + (i - 1) * 20
        hashes[i] = binToHex(string.sub(chunk, start, start + 19))
      end

      return string.sub(chunk, 22), "wants", hashes
    end

    -- SEND - 11Mxxxxx [Mxxxxxxx] deflated data
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
    local body = string.sub(chunk, i, i + length - 1)
    body = inflate(body, 1)
    return string.sub(chunk, i + length), "send", body

  end

  -- "\0" message "\0" Error message
  if head == 0 then
    local term = string.find(chunk, "\0", 2, true)
    if not term then return end
    return string.sub(chunk, term + 1), "error", string.sub(chunk, 2, term - 1)
  end

  -- Text frame with \n terminator
  local term = string.find(chunk, "\n", 1, true)
  -- Make sure we have all data up to the terminator
  if not term then return end

  local line = string.sub(chunk, 1, term - 1)
  local name, message = string.match(line, "^([^ ]+) *(.*)$")
  assert(name, "Invalid message")
  return string.sub(chunk, term + 1), name, #message > 0 and message or nil
end
exports.decode = decode

local encoders = {}
exports.encoders = encoders

-- WANTS - 10xxxxxx (xxxxxx + 1) number of 20 byte raw hashes
function encoders.wants(hashes)
  assert(#hashes > 0, "Can't sent empty wants list")
  local data = {}
  for i = 1, #hashes do
    data[i] = hexToBin(hashes[i])
  end
  return string.char(128 + #hashes - 1) .. table.concat(data, "")
end

-- SEND - 11Mxxxxx [Mxxxxxxx] data
--        (M) is more flag, x is variable length unsigned int
function encoders.send(data)
  -- TDEFL_WRITE_ZLIB_HEADER             = 0x01000,
  -- 4095=Huffman+LZ (slowest/best compression)
  data = deflate(data, 0x01000 + 4095)
  local length = #data
  local head = ""
  local more = 0
  while length >= 0x20 do
    local n = length % 0x80
    head = string.char(more + n) .. head
    more = 0x80
    length = (length - n) / 0x80
  end
  if more > 0 then more = 0x20 end
  head = string.char(0xc0 + more + length) .. head
  return head .. data
end

function encoders.error(message)
  return "\0" .. message .. "\0"
end

local function encode(name, data)
  local encoder = encoders[name]
  if encoder then return encoder(data) end
  if not data then
    return name .. "\n"
  end
  assert(not string.find(data, "\n", 1, true), "No newlines allowed in messages")
  return name .. ' ' .. data .. "\n"
end
exports.encode = encode

function exports.makeRemote(rawRead, rawWrite)
  local buffer = ""
  -- read
  local function read()
    while true do
      if #buffer > 0 then
        local extra, name, data = decode(buffer)
        if extra then
          buffer = extra
          -- p("network read", name, data and (#data <=60 and data or #data))
          assert(name ~= 'error', data)
          return name, data
        end
      end
      local chunk, err = rawRead()
      if err then return nil, err end
      -- p("INPUT", chunk)
      if not chunk then return end
      buffer = buffer .. chunk
    end
  end

  local function readAs(expectedName)
    local name, data = read()
    assert(expectedName == name, "Expected " .. expectedName .. ", but found " .. name)
    return data
  end

  local function writeAs(name, data)
    -- p("network write", name, data and (#data <=60 and data or #data))
    if not name then return rawWrite() end
    local encoded = encode(name, data)
    -- p("OUTPUT", encoded)
    return rawWrite(encoded)
  end

  return {
    read = read,
    readAs = readAs,
    writeAs = writeAs,
  }
end
