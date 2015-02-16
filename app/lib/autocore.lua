local log = require('./log')
local fs = require('coro-fs')
local env = require('env')
local makeDb = require('../lib/db')
local makeCore = require('../lib/core')

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
  config.defaultUpstream = "ws://lit.luvit.io/"
  if not loaded then
    config.upstream = config.defaultUpstream
  end
  dirty = true
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

