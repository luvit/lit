local log = require('../lib/log')
local config = require('../lib/config')
local uv = require('uv')
local pathJoin = require('luvi').path.join
local readPackageFs = require('../lib/read-package').readFs

local db = config.db

if not (config.key and config.name and config.email) then
  error("Please run `lit auth` to configure your username")
end

local meta = assert(readPackageFs(pathJoin(uv.cwd(), args[2] or '.')))
log("publishing", meta.name)
db.publish(meta.name)
