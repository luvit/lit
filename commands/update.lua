local log = require('log').log
local updater = require('auto-updater')
local uv = require('uv')
local pathJoin = require('luvi').path.join
local exec = require('exec')
local prompt = require('prompt')(require('pretty-print'))
local miniz = require('miniz')
local binDir = pathJoin(uv.exepath(), "..")


local function updateLit()
  local config = require('autoconfig')
  config.checked = nil
  config.toupdate = nil
  config.save()
  return updater.check(require('../package'), uv.exepath())
end

local function updateLuvit()
  local luvitPath = pathJoin(binDir, "luvit")
  if require('ffi').os == "Windows" then
    luvitPath = luvitPath .. ".exe"
  end
  if uv.fs_stat(luvitPath) then
    local bundle = require('luvi').makeBundle({luvitPath})
    local fs = {
      readFile = bundle.readfile,
      stat = bundle.stat,
    }
    return updater.check(require('pkg').query(fs, "."), luvitPath)
  else
    return updater.check({ name = "luvit/luvit" }, luvitPath)
  end
end

local function updateLuvi()
  local target = pathJoin(binDir, "luvi")
  if require('ffi').os == "Windows" then
    target = target .. ".exe"
  end
  local new, old
  local toupdate = require('luvi').version
  if uv.fs_stat(target) then
    local stdout = exec(target, "-v")
    local version = stdout:match("luvi (v[^ \n]+)")
    if version and version == toupdate then
      log("luvi is up to date", version, "highlight")
      return
    end

    if version then
      log("found system luvi", version)
      local res = prompt("Are you sure you wish to update " .. target .. " to luvi " .. toupdate .. "?", "Y/n")
      if not res:match("[yY]") then
        log("canceled update", version, "err")
        return
      end
    end

    log("updating luvi", toupdate)
    new = target .. ".new"
    old = target .. ".old"
  else
    log("installing luvi binary", target, "highlight")
    old = nil
    new = target
  end

  local fd = assert(uv.fs_open(new, "w", 511)) -- 0777
  local source = uv.exepath()
  local reader = miniz.new_reader(source)
  local binSize
  if reader then
    -- If contains a zip, find where the zip starts
    binSize = reader:get_offset()
  else
    -- Otherwise just read the file size
    binSize = uv.fs_stat(source).size
  end
  local fd2 = assert(uv.fs_open(source, "r", 384)) -- 0600
  assert(uv.fs_sendfile(fd, fd2, 0, binSize))
  uv.fs_close(fd2)
  uv.fs_close(fd)
  if old then
    log("replacing luvi binary", target, "highlight")
    uv.fs_rename(target, old)
    uv.fs_rename(new, target)
    uv.fs_unlink(old)
    log("luvi update complete", toupdate, "success")
  else
    log("luvi install complete", toupdate, "success")
  end
end

local commands = {
  luvi = updateLuvi,
  luvit = updateLuvit,
  lit = updateLit,
  all = function ()
    updateLit()
    updateLuvit()
    updateLuvi()
  end
}
local cmd = commands[args[2] or "all"]
if not cmd then
  error("Unknown update command: " .. args[2])
end
cmd()
