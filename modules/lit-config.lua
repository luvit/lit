local log = require('lit-log')
local fs = require('coro-fs')
local env = require('env')

local configFile
if require('ffi').os == "Windows" then
  configFile = env.get("APPDATA") .. "\\litconfig"
else
  configFile = env.get("HOME") .. "/.litconfig"
end

local config = {}
local data = fs.readFile(configFile)
if data then
  log("config file", configFile)
  for key, value in string.gmatch(data, "([^:\n]+): *([^\n]+)") do
    config[key] = value
  end
end

local function save()
  local lines = {}
  for key, value in pairs(config) do
    lines[#lines + 1] = key .. ": " .. value
  end
  fs.writeFile(configFile, table.concat(lines, "\n"))
end

return setmetatable(config, {
  __index = {
    save = save
  }
})
