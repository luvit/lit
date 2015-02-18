local config = require('../lib/autocore').config
local log = require('../lib/log')

log("upstream", "disabled", "nil")
config.upstream = nil
config.save()
