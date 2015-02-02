local config = require('../lib/config')
local semver = require('creationix/semver')
local readPackage = require('../lib/read-package').read
local parseVersion = require('../lib/parse-version')
local db = config.db

return function (list)
  local deps = {}

  local addDep, parseList

  function addDep(name, version)
    local existing = deps[name]
    local match, hash = db.match(name, version)
    if not match then
      if version then
        error("No matching package: " .. name .. '@' .. version)
      else
        error("No such package: " .. name)
      end
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

  return deps
end
