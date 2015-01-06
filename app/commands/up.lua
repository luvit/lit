local config = require('../lib/config')
local log = require('../lib/log')

local upstream = args[2] or config.defaultUpstream
log("upstream", upstream)
config.upstream = upstream
config.save()
