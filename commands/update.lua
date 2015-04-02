local meta = require('../package')
local updater = require('auto-updater')
local toupdate = updater.check(meta)
local log = require('log')
if not toupdate then
  log("newer than remote", meta.version, "err")
  return
end
if toupdate == meta.version then
  log("up to date", meta.version, "highlight")
  return
end

local core = require('autocore')
local prompt = require('prompt')(require('pretty-print'))
local uv = require('uv')
local target = uv.exepath()

local res = prompt("Do you sure you wish to update " .. target .. " to lit version " .. toupdate .. "?", "Y/n")
if not res:match("[yY]") then
  log("canceled update", meta.version, "err")
  return
end


local new = target .. ".new"
local old = target .. ".old"
core.makeUrl("lit://" .. meta.name .. "@" .. toupdate, new)
log("replacing binary", target, "highlight")
uv.fs_rename(target, old)
uv.fs_rename(new, target)
uv.fs_unlink(old)
log("update complete", toupdate, "success")
