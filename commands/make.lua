return function ()
  local core = require('core')()
  local uv = require('uv')
  local pathJoin = require('luvi').path.join
  local fs = require("coro-fs")
  local json = require "json"
  local dump = require "serpent".dump

  local cwd = uv.cwd()
  local source = args[2] and pathJoin(cwd, args[2])
  local target = args[3] and pathJoin(cwd, args[3])
  local luvi_source = args[4] and pathJoin(cwd, args[4])

  local needsCleanup
  local expectedLitPackageJsonPath = cwd .. "/lit-package.json"
  local expectedLitPackageLuaPath = cwd .. "/package.lua"
  if fs.stat(expectedLitPackageJsonPath) and not fs.stat(expectedLitPackageLuaPath) then
    -- This isn't great, but we don't want to delete regular package definitions if they exist
    print("Found Lit Package Definition at " .. expectedLitPackageJsonPath)
    local fileContents = fs.readFile(expectedLitPackageJsonPath)
    local table = json.decode(fileContents)
    fs.writeFile(expectedLitPackageLuaPath, dump(table))
    print("Created Lua package definition at " .. expectedLitPackageLuaPath)
    needsCleanup = true
  end

  if not source or uv.fs_access(source, "r") then
    core.make(source or cwd, target, luvi_source)
  else
    core.makeUrl(args[2], target, luvi_source)
  end

  if needsCleanup then
    print("Cleaning up temporary lua package definition at " .. expectedLitPackageLuaPath)
    fs.unlink(expectedLitPackageLuaPath)
  end

end
