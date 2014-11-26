local uv = require('uv')
local fs = require('./fs')
local db = require('./git-fs')("test.git")
local pathJoin = require('luvi').path.join
local modes = require('./git').modes


local function loadPackage(db, base)
  -- Load the package config
  local configPath = pathJoin(base, "package.lua")
  local err, config = fs.readFile(configPath)
  assert(not err, err)
  config = assert(loadstring("return " .. config, configPath))
  config = assert(setfenv(config, {})())

  local rules
  if config.files then
    rules = {}
    for i = 1, #config.files do
      local file = config.files[i]
      local include = true
      if string.sub(file, 1, 1) == "!" then
        file = string.sub(file, 2)
        include = false
      end
      file = string.gsub(file, "[./-]", "%%%1")
      file = string.gsub(file, "%*%*?", function (m)
        return m == "**" and ".+"
                         or "[^/]+"
      end)
      file = "^" .. file .. "$"
      rules[i] = {
        include = include,
        pattern = file
      }
    end
  else
    -- Default to including only lua files
    rules = {{true, "^.*%.lua$"}}
  end

  p{rules=rules}

  local importTree

  function importTree(path)
    local entries = {}
    fs.scandir(pathJoin(base, path), function (entry)
      local filename = pathJoin(path, entry.name)

      -- Apply the rules to see if this file should be included
      local include = entry.type == "DIR"
      for i = 1, #rules do
        if string.match(filename, rules[i].pattern) then
          include = rules[i].include
          print("MATCH", filename, include, rules[i].pattern)
        end
      end
      if not include then return end

      local hash, mode
      if entry.type == "DIR" then
        hash = importTree(filename)
        mode = modes.tree
      else
        local fullPath = pathJoin(base, filename)
        local err, stat, body
        err, stat = fs.lstat(fullPath)
        p(stat)
        assert(not err, err)
        if stat.type == "LINK" then
          mode = modes.sym
          err, body = fs.readlink(fullPath)
        else
          err, body = fs.readFile(fullPath)
          mode = (bit.band(stat.mode, 73) > 0) and modes.exec or modes.blob
        end
        assert(not err, err)
        hash = db:save(body, "blob")
      end

      p(filename, mode, hash)

      -- Don't include empty trees
      if hash == "4b825dc642cb6eb9a060e54bf8d69288fbee4904" then return end

      entries[#entries + 1] = {
        name = entry.name,
        mode = mode,
        hash = hash,
      }
    end)
    p(entries)
    return db:save(entries, "tree")
  end

  return importTree('.')
end


coroutine.wrap(function ()
  db:init()
  print(loadPackage(db, pathJoin(uv.cwd(), "sample-lib")))
end)()

