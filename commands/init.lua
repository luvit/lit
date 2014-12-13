local prompt = require('prompt')
local fs = require('coro-fs')
local env = require('env')
local config = require('lit-config')

local function check(name)
  local message = name .. ": "
  local original = config[name]
  if original then
    message = message .. "(" .. original .. ") "
  end
  local value = config[name]
  repeat
    value = assert(prompt(message))
    if original and #value == 0 then
      value = original
    end
  until #value > 0
  config[name] = value
end

local home = env.get("HOME")
if home and not config["private key"] then
  local keypath = home .. '/.ssh/id_rsa'
  if fs.access(keypath, "r") then
    config["private key"] = keypath
  end
end
if not config.upstream then
  config.upstream = "lit.luvit.io"
end

check("upstream")
check("github name")
check("private key")

-- TODO: verify private key matches with github name
-- Store fingerprint in config

config.save()



