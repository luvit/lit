local hexToBin = require('creationix/hex-bin').hexToBin
local JSON = require('json')

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

-- QUERY - query "\n\n"
-- REPLY - reply "\n\n"
function exports.query(line)
  assert(not string.match(line, "\n", 1, true), "Query cannot contain \n")
  return line .. "\n"
end

function exports.reply(data)
  return JSON.stringify(data) .. "\n"
end

assert(exports.want("5b2d2d2d32302d627974652d686173682d2d2d5d") == '\128[---20-byte-hash---]')

assert(exports.send("Hello World\n") == "\204Hello World\n")
local data = string.rep("0123456789", 100)
assert(exports.send(data) == string.char(128 + 64 + 32 + 7, 104) .. data)
data = string.rep("0123456789", 1000)
assert(exports.send(data) == string.char(128 + 64 + 32, 128 + 78, 16) .. data)
assert(exports.query("Who are you?") == "Who are you?\n")
assert(exports.reply("There are those who call me Tim!") == '"There are those who call me Tim!"\n')
assert(exports.reply({{1,2,3},true,false}) == '[[1,2,3],true,false]\n')
