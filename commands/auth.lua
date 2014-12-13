local prompt = require('prompt')
local fs = require('coro-fs')
local env = require('env')
local config = require('lit-config')
local log = require('lit-log')
local sshRsa = require('ssh-rsa')

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

check("github name")

if not config["private key"] then
  local path = env.get("HOME") .. '/.ssh/id_rsa'
  if fs.access(path, "r") then
    config["private key"] = path
  else
    check("private key")
  end
end

local fingerprint = sshRsa.fingerprint(
  sshRsa.loadPrivate(fs.readFile(config["private key"]))
)
log("ssh fingerprint", fingerprint)

-- TODO: verify ownership of username using key

config.save()



