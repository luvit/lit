local log = require('../lib/log')
local config = require('../lib/config')
local uv = require('uv')
local pathJoin = require('luvi').path.join
local semver = require('creationix/semver')
local evalPackage = require('../lib/read-package').eval
local fs = require('creationix/coro-fs')

local list
if #args == 1 then
  local packagePath = pathJoin(uv.cwd(), "package.lua")
  local data = fs.readFile(packagePath)
  local meta = data and evalPackage(data, packagePath)
  list = meta and meta.dependencies
  if list then
    log("install deps", packagePath)
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

local db = config.db

p(list)
for i = 1, #list do
  local name, version = unpack(list[i])

  local target = pathJoin(uv.cwd(), "modules", name)

  local match, hash = db.match(name, version)
  if not match then
    -- TODO: check upstream if no match can be found locally
    error("No such package in local database matching: " .. name .. ' ' .. version)
  end

  db.export(target, hash)

end


