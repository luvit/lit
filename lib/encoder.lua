local hexToBin = require('creationix/hex-bin').hexToBin

-- WANT - 10xxxxxx (groups of 20 bytes)
function exports.wants(wants)
  assert(type(wants) == "table")
  local num = #wants
  assert(num > 0 and num <= 0x40, "Must have between 1 and 0x40 wants")
  local parts = {}
  for i = 1, num do
    parts[i] = hexToBin(wants[i])
  end
  return string.char(0x80 + num - 1) .. table.concat(parts)
end

-- SEND - 11Mxxxxx [Mxxxxxxx] data
--        (M) is more flag, x is variable length unsigned int
function exports.send(data)
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

-- QUERY - "?" query "\n\n"
function exports.query(line)
  assert(not string.match(line, "\n\n", 1, true), "Line cannot contain \n\n")
  return "?" .. line .. "\n\n"
end

-- REPLY - "!" reply "\n\n"
function exports.reply(line)
  assert(not string.match(line, "\n\n", 1, true), "Line cannot contain \n\n")
  return "!" .. line .. "\n\n"
end

assert(exports.wants({
  "5b2d2d2d32302d627974652d686173682d2d2d5d",
  "3c3d3d20323020627974652068617368203d3d3e"
}) == '\129[---20-byte-hash---]<== 20 byte hash ==>')

assert(exports.send("Hello World\n") == "\204Hello World\n")
local data = string.rep("0123456789", 100)
assert(exports.send(data) == string.char(128 + 64 + 32 + 7, 104) .. data)
data = string.rep("0123456789", 1000)
assert(exports.send(data) == string.char(128 + 64 + 32, 128 + 78, 16) .. data)
assert(exports.query("Who are you?") == "?Who are you?\n\n")
assert(exports.reply("There are those who call me Tim!") == "!There are those who call me Tim!\n\n")
