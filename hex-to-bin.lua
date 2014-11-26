local function hexToBin(cc)
  return string.char(tonumber(cc, 16))
end

return function (hex)
  return string.gsub(hex, "..", hexToBin)
end
