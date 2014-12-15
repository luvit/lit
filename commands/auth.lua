local prompt = require('../lib/prompt')
local fs = require('../lib/coro-fs')
local env = require('env')
local config = require('../lib/lit-config')
local log = require('../lib/lit-log')
local sshRsa = require('../lib/ssh-rsa')

local function confirm(name, value)
  if value then
    config[name] = value
    log(name, value)
  else
    config[name] = prompt(name, config[name])
  end
end

confirm("github name", args[2])
-- TODO: preload with: git config --get user.name
confirm("name", args[3])
-- TODO: preload with: git config --get user.email
confirm("email", args[4])

if not config["private key"] then
  local path = env.get("HOME") .. '/.ssh/id_rsa'
  if fs.access(path, "r") then
    config["private key"] = path
  else
    confirm("private key")
  end
end

local fingerprint = sshRsa.fingerprint(
  sshRsa.loadPrivate(fs.readFile(config["private key"]))
)
log("ssh fingerprint", fingerprint)

-- TODO: verify ownership of username using key

config.save()



