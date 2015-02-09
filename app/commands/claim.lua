local config = require('../lib/config')
local db = config.db
if #args ~= 2 then
  error("Usage: lit claim orgname")
end
assert(db.claim(config, args[2]))
