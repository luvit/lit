local log = require('log').log
local updater = require('auto-updater')
local uv = require('uv')
local pathJoin = require('luvi').path.join
local exec = require('exec')
local prompt = require('prompt')(require('pretty-print'))
local miniz = require('miniz')
local binDir = pathJoin(uv.exepath(), "..")
local request = require('coro-http').request
local semver = require('semver')
local jsonParse = require('json').parse
local luviUrl = require('luvi-url')
local fs = require('coro-fs')

-- Returns current version, latest version and latest compat version.
local function checkUpdate()
  -- Read the current lit version
  local meta = require('../package')
  local version = semver.normalize(meta.version)
  -- Match against the published lit versions
  local head, body = request("GET", "http://lit.luvit.io/packages/luvit/lit")
  if head.code ~= 200 then
    error("Expected 200 response from lit server, but got " .. head.code)
  end
  local versions = assert(jsonParse(body), "Problem parsing JSON response from lit")
  local key
  local best = semver.match(version, function ()
    key = next(versions, key)
    return key
  end)
  key = nil
  local latest = semver.match(nil, function ()
    key = next(versions, key)
    return key
  end)
  return version, latest, best
end

local version, latest, best = checkUpdate()
local toupdate
print("Detected running lit version " .. version)
if version == latest then
  print("Lit is up to date")
elseif not best or version == best then
  print("Major update available to version " .. latest);
  toupdate = latest
elseif best then
  print("Update available to version " .. best)
  toupdate = best
elseif not semver.gte(latest, version) then
  print("Lit version is newer than latest published version " .. latest)
else
  print("Unknown version series")
end

if toupdate then
  local target = uv.exepath()
  local stdout = exec(target, "-v")
  if not stdout:match("^lit version:") then
    print("Current binary (" .. target .. ") is not lit")
    if jit.os == "Windows" then
      target = "C:\\luvit\\lit.exe"
    else
      target = "/usr/local/bin/lit"
    end
    print("defaulting to " .. target .. " for target")
  end

  -- Download meta
  local url = "http://lit.luvit.io/packages/luvit/lit/v" .. toupdate
  local head, body = request("GET", url)
  if head.code ~= 200 then
    error("Expected 200 response from lit server, but got " .. head.code)
  end
  local meta = jsonParse(body)

  -- Ensure proper luvi binary
  url = luviUrl(meta.luvi)
  print("Downloading " .. url .. "...")
  head, body = request("GET", url)
  if head.code ~= 200 then
    error("Expected 200 response from lit server, but got " .. head.code)
  end

  local tempPath = pathJoin(uv.cwd(), "lit-temp")

  local fd = assert(fs.open(tempPath, "w", 493))
  fs.write(fd, body)

  -- Download zip
  url = "https://lit.luvit.io/packages/luvit/lit/v" .. toupdate .. ".zip"
  print("Downloading " .. url .. "...")
  head, body = request("GET", url)
  if head.code ~= 200 then
    error("Expected 200 response from lit server, but got " .. head.code)
  end

  -- build zip using zip and luvi
  fs.write(fd, body)
  fs.close(fd)

  -- replace installed lit binary
  local old = fs.stat(target)
  if old then
    fs.rename(target, target .. ".old")
  end
  fs.rename(tempPath, target)
  if old then
    fs.unlink(target .. ".old")
  end

  -- run update recursivly as detached child and kill self
end

-- TODO: check for luvi/luvit updates

-- local function updateLuvit()
--   local luvitPath = pathJoin(binDir, "luvit")
--   if require('ffi').os == "Windows" then
--     luvitPath = luvitPath .. ".exe"
--   end
--   if uv.fs_stat(luvitPath) then
--     local bundle = require('luvi').makeBundle({luvitPath})
--     local fs = {
--       readFile = bundle.readfile,
--       stat = bundle.stat,
--     }
--     return updater.check(require('pkg').query(fs, "."), luvitPath)
--   else
--     return updater.check({ name = "luvit/luvit" }, luvitPath)
--   end
-- end
--
-- local function updateLuvi()
--   local target = pathJoin(binDir, "luvi")
--   if require('ffi').os == "Windows" then
--     target = target .. ".exe"
--   end
--   local new, old
--   local toupdate = require('luvi').version
--   if uv.fs_stat(target) then
--     local stdout = exec(target, "-v")
--     local version = stdout:match("luvi (v[^ \n]+)")
--     if version and version == toupdate then
--       log("luvi is up to date", version, "highlight")
--       return
--     end
--
--     if version then
--       log("found system luvi", version)
--       local res = prompt("Are you sure you wish to update " .. target .. " to luvi " .. toupdate .. "?", "Y/n")
--       if not res:match("[yY]") then
--         log("canceled update", version, "err")
--         return
--       end
--     end
--
--     log("updating luvi", toupdate)
--     new = target .. ".new"
--     old = target .. ".old"
--   else
--     log("installing luvi binary", target, "highlight")
--     old = nil
--     new = target
--   end
--
--   local fd = assert(uv.fs_open(new, "w", 511)) -- 0777
--   local source = uv.exepath()
--   local reader = miniz.new_reader(source)
--   local binSize
--   if reader then
--     -- If contains a zip, find where the zip starts
--     binSize = reader:get_offset()
--   else
--     -- Otherwise just read the file size
--     binSize = uv.fs_stat(source).size
--   end
--   local fd2 = assert(uv.fs_open(source, "r", 384)) -- 0600
--   assert(uv.fs_sendfile(fd, fd2, 0, binSize))
--   uv.fs_close(fd2)
--   uv.fs_close(fd)
--   if old then
--     log("replacing luvi binary", target, "highlight")
--     uv.fs_rename(target, old)
--     uv.fs_rename(new, target)
--     uv.fs_unlink(old)
--     log("luvi update complete", toupdate, "success")
--   else
--     log("luvi install complete", toupdate, "success")
--   end
-- end
--
-- local commands = {
--   luvi = updateLuvi,
--   luvit = updateLuvit,
--   lit = updateLit,
--   all = function ()
--     updateLit()
--     updateLuvit()
--     updateLuvi()
--   end
-- }
-- local cmd = commands[args[2] or "all"]
-- if not cmd then
--   error("Unknown update command: " .. args[2])
-- end
-- cmd()
