local function binToHex(c)
  return string.format("%02x", string.byte(c, 1))
end

return function(bin)
  return string.gsub(bin, ".", binToHex)
end
