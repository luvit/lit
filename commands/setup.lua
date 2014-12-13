local prompt = require('prompt')
local fs = require('coro-fs')
local env = require('env')
local config = require('lit-config')

local function check(name)
  repeat
    config[name] = assert(prompt(name .. ': ', config[name]))
  until #config[name] > 0
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



