local core = require('../lib/autocore')
local uv = require('uv')
local pathJoin = require('luvi').path.join


local cwd = uv.cwd()
local app = args[2] and pathJoin(cwd, args[2]) or cwd
local target = args[3] and pathJoin(cwd, args[3])
core.make(app, target)
