local log = require('../lib/log')
local config = require('../lib/config')
local uv = require('uv')
local pathJoin = require('luvi').path.join
local readPackageFs = require('../lib/read-package').readFs
local db = config.db
local storage = db.storage

local parseDeps = require('../lib/parse-deps')

local list
if #args == 1 then
  local meta, packagePath = assert(readPackageFs(uv.cwd()))
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

local deps = parseDeps(list)
p(deps)

for alias, value in pairs(deps) do
  local name = value.name
  if not storage.readTag(name, value.version) then
    log("pulling package", name .. '@' .. value.version)
    db.pull(name, value.version)
  end
  log("installing package", name .. '@' .. value.version)
  local target = pathJoin(uv.cwd(), "modules", alias)
  db.export(target, value.hash)
end
