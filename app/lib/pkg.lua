--[[
Package Commands
================

These commands work with packages as units.  Consumes the db interface.

pkg.query(path) -> path, meta               - Query an on-disk path for package info.
pky.normalize(meta) -> author, tag, version - Extract and normalize pkg info
]]

local isFile = require('git').modes.isFile
local semver = require('semver')
local fs = require('coro-fs')
local pathJoin = require('luvi').path.join
local listToMap = require('git').listToMap

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
  if err then
    if err:match("^EISDIR:") then
      packagePath = path .. "/"
      data, err = fs.readFile(pathJoin(path, "package.lua"))
      if err and not err:match("^ENOENT:") then error(err) end
      if not data then
        data, err = fs.readFile(pathJoin(path, "init.lua"))
        if err and not err:match("^ENOENT:") then error(err) end
      end
    elseif err:match("^ENOENT:") then
      packagePath = packagePath .. ".lua"
      data, err = fs.readFile(packagePath)
    end
  end
  if not data then
    return data, err or "Can't find package at " .. path
  end
  local meta = evalModule(data, packagePath)

  return meta, packagePath
end

function exports.queryDb(db, hash)
  local kind, value = db.load(hash)
  if kind == "tag" then
    kind, value = db.load(value.object)
  end
  local meta
  if kind == "tree" then
    local path = "tree:" .. hash
    local tree = listToMap(value)
    local entry = tree["package.lua"]
    if entry then
      path = path .. "/package.lua"
    else
      entry = tree["init.lua"]
      path = path .. "/init.lua"
    end
    if not (entry and isFile(entry.mode)) then
      return nil, "ENOENT: No package.lua or init.lua in tree:" .. hash
    end
    meta = evalModule(db.loadAs("blob", entry.hash), path)
  elseif kind == "blob" then
    meta = evalModule(value, "blob:" .. hash)
  else
    error("Illegal kind: " .. kind)
  end
  return meta, kind
end

function exports.normalize(meta)
  local author, tag = meta.name:match("^([^/]+)/(.*)$")
  return author, tag, semver.normalize(meta.version)
end
