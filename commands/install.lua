local log = require('../lib/log')
local config = require('../lib/config')
local uv = require('uv')
local pathJoin = require('luvi').path.join
local semver = require('creationix/semver')
local readPackageFs = require('../lib/read-package').readFs
local readPackage = require('../lib/read-package').read
local parseVersion = require('../lib/parse-version')
local db = config.db

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

local deps = {}

local addDep, parseList

function addDep(name, version)
  local existing = deps[name]
  local match, hash = db.match(name, version)
  if not match then
    error("Can't find match for " .. name .. '@' .. tostring(version))
  end
  if existing then
    if existing.version ~= match then
      print("WARNING: Deep dependency mismatch for " .. name .. ", installing newer version")
    end
    -- If we already have the same or newer version, ignore this dependency
    if semver.gte(existing.version, match) then return end
  end
  deps[name] = {
    version = match,
    hash = hash
  }
  local tag = assert(db.loadAs("tag", hash))
  local _, meta = readPackage(db, tag.object)
  if meta.dependencies then
    parseList(meta.dependencies)
  end
end

function parseList(list)
  for i = 1, #list do
    addDep(parseVersion(list[i]))
  end
end

parseList(list)

for name, value in pairs(deps) do
  if not db.read(name, value.version) then
    log("pulling package", name .. '@' .. value.version)
    db.pull(name, value.version)
  end
  log("installing package", name .. '@' .. value.version)
  local target = pathJoin(uv.cwd(), "modules", name)
  db.export(target, value.hash)
end


