local log = require('log')
local core = require('core')()
for key, value in pairs(core.config) do
  log(key, value, "string")
end
