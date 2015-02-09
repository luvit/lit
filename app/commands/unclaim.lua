local config = require('../lib/config')
local db = config.db
if #args ~= 2 then
  error("Usage: lit unclaim orgname")
end
assert(db.unclaim(config, args[2]))
