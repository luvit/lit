local core = require('../lib/autocore')
if #args ~= 2 then
  error("Usage: lit unclaim orgname")
end
assert(core.unclaim(args[2]))
