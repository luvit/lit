local log = require('../lib/log')
local config = require('../lib/config')
local uv = require('uv')
local pathJoin = require('luvi').path.join
local semverMatch = require('creationix/semver')
local export = require('../lib/export')
local storage = require('../lib/storage')
local readPackage = require('../lib/read-package')

local list = {}

if #args == 1 then
  local meta = assert(readPackage(pathJoin(uv.cwd(), "package.lua")))
  p(meta)
  error("TODO: install deps in local package.lua")
end
for i = 2, #args do
  local name = args[i]
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


end
