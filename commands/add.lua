local log = require('../lib/log')
local config = require('../lib/config')
local uv = require('uv')
local pathJoin = require('luvi').path.join
local prompt = require('creationix/prompt')
local import = require('../lib/import')
local storage = require('../lib/storage')
local fs = require('creationix/coro-fs')
local readPackage = require('../lib/read-package')

if not (config.key and config.name and config.email) then
  error("Please run `lit auth` to configure your username")
end

local path = pathJoin(uv.cwd(), args[2] or prompt("package path"))

local stat = fs.stat(path)

-- Guess some stuff from the
local packagePath
if stat.type == "file" then
  packagePath = path
else
  packagePath = pathJoin(path, "package.lua")
end
local meta = readPackage(packagePath)
meta = type(meta) == "table" and meta or {}

local name = args[3] or meta.name or prompt("package name")
assert(string.match(name, "^[^ /\\][^ ]*[^ /\\]$"), "invalid package name")
if not string.match(name, "/") then
  name = config["github name"] .. '/' .. name
end
local version = args[4] or meta.version or prompt("semantic version")
version = string.match(version, "%d+%.%d+%.%d+$")
assert(version, "invalid version number")
local message = args[5] or ""

local tag = name .. '/v' .. version
if storage:read(tag) then
  error("Tag already exists: " .. tag)
end

log("path", path)
log("tag", tag)

import(config, storage, path, tag, message)
