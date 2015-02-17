
local db = require('../lib/db')("test")
local core = require('../lib/core')(db)

p(core)

local config = require('../lib/config')
local author, tag, version, tagHash = core.tag("app/modules/ssh-rsa.lua", config.name, config.email, config.key)
p{author=author,tag=tag,version=version, tagHash=tagHash}
author, tag, version, tagHash = core.tag("app/modules/ssh-rsa.lua", config.name, config.email, config.key)
p{author=author,tag=tag,version=version, tagHash=tagHash}

