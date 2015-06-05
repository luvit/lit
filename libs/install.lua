local pkg = require('pkg')
local queryDb = pkg.queryDb
local normalize = require('semver').normalize
local getInstalled = require('get-installed')
local export = require('export')
local gte = require('semver').gte
local pathJoin = require('luvi').path.join
local log = require('log')

-- Given a path to a deps folder in the fs, install list of deps
-- Returns full deps report.
return function (db, fs, path, newDeps)

  local deps = getInstalled(fs, pathJoin(path, ".."))

  local addDep, processDeps

  function processDeps(dependencies)
    for alias, dep in pairs(dependencies) do
      local name, version = dep:match("^([^@]+)@?(.*)$")
      if #version == 0 then
        version = nil
      end
      if type(alias) == "number" then
        alias = name:match("([^/]+)$")
      end
      if not name:find("/") then
        error("Package names must include owner/name at a minimum")
      end
      if version then
        version = normalize(version)
      end
      addDep(alias, name, version)
    end
  end

  function addDep(alias, name, version)
    local meta = deps[alias]
    if meta then
      if name ~= meta.name then
        local message = string.format("%s %s ~= %s",
          alias, meta.name, name)
        log("alias conflict", message, "failure")
        return
      end
      if version then
        if not gte(meta.version, version) then
          local message = string.format("%s %s ~= %s",
            alias, meta.version, version)
          log("version conflict", message, "failure")
          return
        elseif meta.version:match("%d+%.%d+%.%d+") ~= version:match("%d+%.%d+%.%d+") then
          local message = string.format("%s %s ~= %s",
            alias, meta.version, version)
          log("version mismatch", message, "highlight")
        end
      end

    else
      local author, pname = name:match("^([^/]+)/(.*)$")
      local match, hash = db.match(author, pname, version)

      if not match then
        error("No such "
          .. (version and "version" or "package") .. ": "
          .. name
          .. (version and '@' .. version or ''))
      end

      meta = assert(queryDb(db, hash))
      meta.hash = hash
      deps[alias] = meta
    end

    if meta.dependencies then
      processDeps(meta.dependencies)
    end

  end

  processDeps(newDeps)

  for alias, meta in pairs(deps) do
    if meta.hash then
      local packagePath = pathJoin(path, alias)
      local tag = db.loadAs("tag", meta.hash)
      if tag.type == "blob" then
        packagePath = packagePath .. ".lua"
      end
      log("installing package", string.format("%s@v%s", meta.name, meta.version), "highlight")
      export(db, tag.object, fs, packagePath)
    end
  end

  return deps
end
