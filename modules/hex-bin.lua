exports.name = "creationix/hex-bin"
exports.version = "1.0.0"

local function binToHex(c)
  return string.format("%02x", string.byte(c, 1))
end

exports.binToHex = function(bin)
  local hex = string.gsub(bin, ".", binToHex)
  return hex
end

local function hexToBin(cc)
  return string.char(tonumber(cc, 16))
end

exports.hexToBin = function (hex)
  local bin = string.gsub(hex, "..", hexToBin)
  return bin
end
