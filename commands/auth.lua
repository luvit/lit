local prompt = require('creationix/prompt')
local fs = require('creationix/coro-fs')
local env = require('env')
local config = require('../lib/config')
local log = require('../lib/log')
local exec = require('../lib/exec')
local sshRsa = require('creationix/ssh-rsa')

local function confirm(name, value)
  if value then
    config[name] = value
    log(name, value)
  else
    config[name] = prompt(name, config[name])
  end
end

local function run(...)
  local stdout, stderr, code, signal = exec(...)
  if code == 0 and signal == 0 then
    return string.gsub(stdout, "%s*$", "")
  else
    return nil, string.gsub(stderr, "%s*$", "")
  end
end

confirm("username", args[2])
confirm("name", args[3] or run("git", "config", "--get", "user.name"))
confirm("email", args[4] or run("git", "config", "--get", "user.email"))

if not config.privateKey then
  local path = env.get("HOME") .. '/.ssh/id_rsa'
  if fs.access(path, "r") then
    config.privateKey = path
  else
    confirm("privateKey")
  end
end

local fingerprint = sshRsa.fingerprint(
  sshRsa.loadPrivate(fs.readFile(config.privateKey))
)
log("ssh fingerprint", fingerprint)

-- TODO: verify ownership of username using key

config.save()



