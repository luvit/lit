local config = require('core')().config
local log = require('log')

log("upstream", "disabled", "nil")
config.upstream = nil
config.save()
