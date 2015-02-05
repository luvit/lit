local config = require('../lib/config')
local semver = require('semver')
local readPackage = require('../lib/read-package').read
local parseVersion = require('../lib/parse-version')
local db = config.db

return function (list)
  local deps = {}

  local addDep, parseList

  function addDep(alias, name, version)
    local existing = deps[alias]
    local match, hash = db.match(name, version)
    if not match then
      if version then
        error("No matching package: " .. name .. '@' .. version)
      else
        error("No such package: " .. name)
      end
    end
    if existing then
      if existing.name ~= name then
        print("Warning: Alias conflict between " .. existing.name .. " and " .. name)
        return
      end
      if existing.version ~= match then
        print("WARNING: Deep dependency mismatch for " .. name .. ", installing newer version")
      end
      -- If we already have the same or newer version, ignore this dependency
      if semver.gte(existing.version, match) then return end
    end
    deps[alias] = {
      name = name,
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
    for alias, dep in pairs(list) do
      if type(alias) == "number" then
        alias = string.match(dep, "/([^@]+)")
      end
      addDep(alias, parseVersion(dep))
    end
  end

  parseList(list)

  return deps
end
