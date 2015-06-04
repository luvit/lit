local pathJoin = require('luvi').path.join
local pkgQuery = require('pkg').query

return function (fs, path)
  local deps = {}
  local function check(dir)
    for entry in fs.scandir(dir) do
      local baseName
      if entry.type == "file" then
        baseName = entry.name:match("^(.*)%.lua$")
      elseif entry.type == "directory" then
        baseName = entry.name
      end
      if baseName then
        local path = pathJoin(dir, entry.name)
        local meta = pkgQuery(fs, path)
        if meta then
          meta.location = dir
          deps[baseName] = meta
        end
      end
    end
  end
  check(pathJoin(path, "deps"))
  check(pathJoin(path, "libs"))
  return deps
end
