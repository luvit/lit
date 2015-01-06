local log = require('./log')
local fs = require('creationix/coro-fs')
local env = require('env')
local makeDb = require('../lib/db')

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
  config.defaultUpstream = "lit.luvit.io"
  dirty = true
end

if not config.database or not config.storage then
  local sophia = pcall(require, './sophia.so')
  config.storage = sophia and "sophia" or "git"
  config.database = prefix .. "litdb." .. config.storage
  dirty = true
end

if dirty then save() end

local key
if config.privateKey then
  local keyData = assert(fs.readFile(config.privateKey))
  key = require('openssl').pkey.read(keyData, true)
end

local storage = require('../lib/storage-' .. config.storage)(config.database)
local db = makeDb(storage, config.upstream)

return setmetatable(config, {
  __index = {
    save = save,
    key = key,
    db = db,
  }
})
