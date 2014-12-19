local config = require('../lib/config')
local log = require('../lib/log')

log("upstream", "disabled", "nil")
config.upstream = nil
config.save()
