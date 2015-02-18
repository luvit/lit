local config = require('../lib/autocore').config
local log = require('../lib/log')

local upstream = args[2] or config.defaultUpstream
log("upstream", upstream, "highlight")
config.upstream = upstream
config.save()
