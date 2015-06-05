local pathJoin = require('luvi').path.join
local pkgQuery = require('pkg').query

return function (fs, rootPath)
  local deps = {}
  local function check(dir)
    local iter = fs.scandir(dir)
    if not iter then return end
    for entry in iter do
      local baseName
      if entry.type == "file" then
        baseName = entry.name:match("^(.*)%.lua$")
      elseif entry.type == "directory" then
        baseName = entry.name
      end
      if baseName then
        local path, meta
        path = pathJoin(dir, entry.name)
        meta, path = pkgQuery(fs, path)
        if meta then
          meta.fs = fs
          meta.path = path
          meta.location = dir:match("[^/]+$")
          deps[baseName] = meta
        end
      end
    end
  end
  check(pathJoin(rootPath, "deps"))
  check(pathJoin(rootPath, "libs"))
  return deps
end
