local log = require('../lib/lit-log')
local config = require('../lib/lit-config')
local uv = require('uv')
local pathJoin = require('luvi').path.join
local prompt = require('../lib/prompt')
local semverMatch = require('../lib/semver')
local export = require('../lib/export')
local storage = require('../lib/lit-storage')


local name = args[2] or prompt("package name")

if not string.find(name, "/") then
  if not config["github name"] then
    error("Please speficy a full package name including username")
  end
  name = config["github name"] .. '/' .. name
end

local version = args[3] or "*"

local target = pathJoin(uv.cwd(), "modules", name)

local match = semverMatch(version, storage:versions(name))
if not match then
  -- TODO: check upstream if no match can be found locally
  error("No such package in local database matching: " .. name .. ' ' .. version)
end
version = match

local tag = name .. '/v' .. version
log("package", tag)

log("target", target)

export(config, storage, target, tag)
