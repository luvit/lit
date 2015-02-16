local core = require('../lib/autocore')
local prompt = require('prompt')(require('pretty-print'))
local fs = require('coro-fs')
local env = require('env')
local log = require('../lib/log')
local exec = require('../lib/exec')

local config = core.config
local dirty = false

local function confirm(name, value)
  if not value then
    value = config[name]
  end
  if not value then
    value = prompt(name)
  else
    log(name, value)
  end
  if value ~= config[name] then
    config[name] = value
    dirty = true
  end
  return value
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

local path = (env.get("HOME") or env.get("HOMEPATH")) .. '/.ssh/id_rsa'
if fs.access(path, "r") then
  config.privateKey = path
end
confirm("privateKey")

core.authUser()

if dirty then config.save() end
