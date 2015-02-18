local log = require('../lib/log')
local core = require('../lib/autocore')
for key, value in pairs(core.config) do
  log(key, value, "string")
end
