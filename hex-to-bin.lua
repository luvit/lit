local function hexToBin(cc)
  return string.char(tonumber(cc, 16))
end

return function (hex)
  local bin = string.gsub(hex, "..", hexToBin)
  return bin
end
