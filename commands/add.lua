local log = require('../lib/log')
local config = require('../lib/config')
local uv = require('uv')
local pathJoin = require('luvi').path.join
local db = config.db

if not (config.key and config.name and config.email) then
  error("Please run `lit auth` to configure your username")
end

local path = pathJoin(uv.cwd(), args[2] or '.')
local message = args[3] or ""
local hash = assert(db.import(path))
local name, version, tagHash = db.tag(config, hash, message)
log("added package", name .. "@" .. version .. " " .. tagHash)
