local log = require('../lib/log')
local config = require('../lib/config')
for key, value in pairs(config) do
  log(key, value, "string")
end
