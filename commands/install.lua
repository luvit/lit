local log = require('../lib/log')
local config = require('../lib/config')
local uv = require('uv')
local pathJoin = require('luvi').path.join
local semver = require('creationix/semver')
local export = require('../lib/export')
local storage = require('../lib/storage')
local readPackage = require('../lib/read-package')

local list
if #args == 1 then
  local packagePath = pathJoin(uv.cwd(), "package.lua")
  local meta = assert(readPackage(packagePath))
  if meta.dependencies then
    log("install deps", packagePath)
    list = meta.dependencies
  else
    log("abort", "Nothing to install")
    return
  end
else
  list = {}
  for i = 2, #args do
    local name = args[i]
    list[#list + 1] = name
  end
end

for i = 1, #list do
  local item = list[i]

  -- Prefix current user if owner is left out
  if not string.match(item, "^([^/]+)/") then
    if not config["github name"] then
      error("Please specify a full package name including owner's username")
    end
    item = config["github name"] .. '/' .. item
  end

  -- split out name and version
  local name = string.match(item, "^([^@]+)")
  if not name then
    error("Missing name in dep: " .. list[i])
  end
  local version = string.sub(item, #name + 2)
  if #version == 0 then
    version = nil
  else
    version = semver.normalize(version)
  end
  list[i] = {name, version}

  -- TODO: look up recursive dependencies for deps with package.lua at their root
  -- TODO: resolve conflicts that arise from this.  When conflicts occur, use the
  --       newer version and print a warning.
end

for i = 1, #list do
  local name, version = unpack(list[i])

  local target = pathJoin(uv.cwd(), "modules", name)

  local match = semver.match(version, storage:versions(name))
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


