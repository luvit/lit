local log = require('./log')
local fs = require('coro-fs')
local env = require('env')
local makeDb = require('db')
local makeCore = require('core')

local prefix
if require('ffi').os == "Windows" then
  prefix = env.get("APPDATA") .. "\\"
else
  prefix = env.get("HOME") .. "/."
end

local configFile = env.get("LIT_CONFIG") or (prefix .. "litconfig")

local loaded = false
local config = {}
local data = fs.readFile(configFile)
if data then
  loaded = true
  log("load config", configFile)
  for key, value in string.gmatch(data, "([^:\n]+): *([^\n]+)") do
    config[key] = value
  end
end

local function save()
  if loaded then
    log("update config", configFile)
  else
    log("create config", configFile)
    loaded = true
  end
  local lines = {}
  for key, value in pairs(config) do
    lines[#lines + 1] = key .. ": " .. value
  end
  fs.writeFile(configFile, table.concat(lines, "\n") .. '\n')
end

local dirty = false
if not config.defaultUpstream then
  config.defaultUpstream = "wss://lit.luvit.io/"
  if not loaded then
    config.upstream = config.defaultUpstream
  end
  dirty = true
end

local meta = require('../package')

if config.upstream then
  -- Only check for updates when online
  local now = os.time()
  -- Only check if we haven't checked for a while
  -- TODO: only check if has internet.
  if not config.checked or tonumber(config.checked) < now - 1000 then
    config.checked = os.time()
    dirty = true
    log("checking for update", meta.version)
    if not pcall(function ()
      config.toupdate = require('auto-updater').check(meta)
    end) then
      log("no connection to update server", "lit.luvit.io")
    end
  end

end
if config.toupdate == meta.version then
  config.toupdate = nil
  dirty = true
end

if config.toupdate then
  log("lit update available", config.toupdate, "highlight")
end

if not config.database then
  config.database = prefix .. "litdb.git"
  dirty = true
end

if dirty then save() end

setmetatable(config, {
  __index = {save = save}
})

local privateKey
local function getKey()
  if not config.privateKey then return end
  if privateKey then return privateKey end
  local keyData = assert(fs.readFile(config.privateKey))
  privateKey = require('openssl').pkey.read(keyData, true)
  return privateKey
end

return makeCore(makeDb(config.database), config, getKey)

