local log = require('../lib/lit-log')
local config = require('../lib/lit-config')
local uv = require('uv')
local pathJoin = require('luvi').path.join
local prompt = require('../lib/prompt')
local import = require('../lib/import')
local storage = require('../lib/lit-storage')

if not (config.key and config.name and config.email) then
  error("Please run `lit auth` to configure your username")
end

-- TODO: guess

local path = pathJoin(uv.cwd(), args[2] or prompt("package path"))

local name = args[3] or prompt("package name")
assert(string.match(name, "^[^ /\\][^ ]*[^ /\\]$"), "invalid package name")
local version = args[4] or prompt("semantic version")
version = string.match(version, "%d+%.%d+%.%d+$")
assert(version, "invalid version number")
local message = args[5] or prompt("release notes")

local tag = config["github name"] .. '/' .. name .. '/v' .. version

log("path", path)
log("tag", tag)

import(config, storage, path, tag, message)
