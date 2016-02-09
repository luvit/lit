--[[lit-meta
  name = "creationix/base64"
  description = "A pure lua implemention of base64 using bitop"
  tags = {"crypto", "base64", "bitop"}
  version = "1.0.0"
  license = "MIT"
  author = { name = "Tim Caswell" }
]]

local bit = require 'bit'
local rshift = bit.rshift
local lshift = bit.lshift
local bor = bit.bor
local band = bit.band
local char = string.char
local byte = string.byte
local concat = table.concat
local ceil = math.ceil
local codes = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

return function (str)
  local parts = {}
  local l = ceil(#str / 3)
  for i = 1, l do
    local o = i * 3
    local a, b, c = byte(str, o - 2, o)
    parts[i] = char(
      -- Higher 6 bits of a
      byte(codes, rshift(a, 2) + 1),
      -- Lower 2 bits of a + high 4 bits of b
      byte(codes, bor(
        lshift(band(a, 3), 4),
        b and rshift(b, 4) or 0
      ) + 1),
      -- High 4 bits of b + low 2 bits of c
      b and byte(codes, bor(
        lshift(band(b, 15), 2),
        c and rshift(c, 6) or 0
      ) + 1) or 61, -- 61 is '='
      -- Lower 4 bits of c
      c and byte(band(c, 63) + 1) or 61 -- 61 is '='
    )
  end
  return concat(parts)
end
