local core = require('autocore')
if #args ~= 2 then
  error("Usage: lit claim orgname")
end
assert(core.claim(args[2]))
