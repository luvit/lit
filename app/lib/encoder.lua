local hexToBin = require('creationix/hex-bin').hexToBin

function exports.error(message)
  return "\000" .. message .. "\n"
end

function exports.handshake(versions)
  return "LIT/" .. table.concat(versions, ",") .. "\n"
end

function exports.agreement(version)
  return "LIT/" .. version .. "\n"
end

-- WANT - 10xxxxxx (groups of 20 bytes)
function exports.want(hash)
  return '\128' .. hexToBin(hash)
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

-- message - NAME space seperated args "\n"
function exports.message(name, ...)
  assert(name == string.upper(name), "message name must be upper case")
  local args = {...}
  for i = 1, #args do
    assert(not string.match(args[i], "[ \n]"), "args cannot contain \n or ' '")
  end
  return name .. ' ' .. table.concat(args, " ") .. "\n"
end

assert(exports.want("5b2d2d2d32302d627974652d686173682d2d2d5d") == '\128[---20-byte-hash---]')

assert(exports.send("Hello World\n") == "\204Hello World\n")
local data = string.rep("0123456789", 100)
assert(exports.send(data) == string.char(128 + 64 + 32 + 7, 104) .. data)
data = string.rep("0123456789", 1000)
assert(exports.send(data) == string.char(128 + 64 + 32, 128 + 78, 16) .. data)
assert(exports.message("WHO", "are", "you") == "WHO are you\n")
assert(exports.message("I", "am", "Tim") == "I am Tim\n")
