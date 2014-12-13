local log = require('lit-log')
local fs = require('coro-fs')
local env = require('env')

local configFile
if require('ffi').os == "Windows" then
  configFile = env.get("APPDATA") .. "\\litconfig"
else
  configFile = env.get("HOME") .. "/.litconfig"
end

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

if not config.upstream then
  config.upstream = "lit.luvit.io"
  save()
end

return setmetatable(config, {
  __index = {
    save = save
  }
})
