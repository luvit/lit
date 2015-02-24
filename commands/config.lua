local log = require('log')
local core = require('autocore')
for key, value in pairs(core.config) do
  log(key, value, "string")
end
