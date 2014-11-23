local encoders = {}

local function hexToBin(cc)
  return string.char(tonumber(cc, 16))
end


function encoders.want(hashes)
  local count = #hashes
  local parts = {}
  for i = 0, count - 1, 64 do
    local num = math.min(64, count - i)
    parts[#parts + 1] = 64 + num
    for j = i + 1, i + num do
    end
  end
  local encoded =
  for i = 1, #hashes do


        string.gsub(entry.hash, "..", hexToBin))


end
