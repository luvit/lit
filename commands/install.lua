local log = require('lit-log')
local config = require('lit-config')
local uv = require('uv')
local pathJoin = require('luvi').path.join
local prompt = require('prompt')
local export = require('export')
local storage = require('lit-storage')


local name = args[2] or prompt("package name")

if not string.find(name, "/") then
  name = config["github name"] .. '/' .. name
end

local version = args[3] or "*"

local target = pathJoin(uv.cwd(), "modules", name)

log("package", name)
log("version", version)
log("target", target)


storage:names(function (name)
end)
-- TODO: match against versions in local database

-- TODO: check upstream if no match can be found locally

-- TODO: export once match is found
