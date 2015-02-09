local config = require('../lib/config')
local db = config.db
if #args ~= 3 then
  error("Usage: lit share orgname friendname")
end
assert(db.share(config, args[2], args[3]))
