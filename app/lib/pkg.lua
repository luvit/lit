--[[
Package Commands
================

These commands work with packages as units.  Consumes the db interface.

pkg.query(path) -> path, meta               - Query an on-disk path for package info.
pky.normalize(meta) -> author, tag, version - Extract and normalize pkg info
]]

local git = require('git')
local semver = require('semver')
local fs = require('coro-fs')
local pathJoin = require('luvi').path.join

local function makeAny()
  return setmetatable({},{
    __index = makeAny,
    __call = makeAny,
    __newindex = function () end,
  })
end

local sandbox = { __index = _G }

local function evalModule(data, name)
  local fn = assert(loadstring(data, name))
  local exports = {}
  local module = { exports = exports }
  setfenv(fn, setmetatable({
    module = module,
    exports = exports,
    require = makeAny,
  }, sandbox))
  local success, ret = pcall(fn)
  assert(success, ret)
  local meta = type(ret) == "table" and ret or module.exports
  assert(meta, "Missing exports in " .. name)
  assert(meta.name, "Missing name in package description in " .. name)
  assert(meta.version, "Missing version in package description in " .. name)
  return meta
end


function exports.query(path)
  local packagePath = path
  local data, err = fs.readFile(path)
  if err and err:match("^EISDIR:") then
    packagePath = pathJoin(path, "package.lua")
    data, err = fs.readFile(packagePath)
    if err and not err:match("^ENOENT:") then error(err) end
    if not data then
      packagePath = pathJoin(path, "init.lua")
      data, err = fs.readFile(packagePath)
      if err and not err:match("^ENOENT:") then error(err) end
    end
  end
  assert(data, err or "Can't find package at " .. path)
  return evalModule(data, packagePath), packagePath
end

function exports.normalize(meta)
  local author, tag = meta.name:match("^([^/]+)/(.*)$")
  return author, tag, semver.normalize(meta.version)
end



