--[[
Package Metadata Commands
================

These commands work with packages metadata.

pkg.query(fs, path) -> meta, path           - Query an on-disk path for package info.
pkg.queryDb(db, path) -> meta, kind         - Query an in-db hash for package info.
pky.normalize(meta) -> author, tag, version - Extract and normalize pkg info
]]

local isFile = require('git').modes.isFile
local semver = require('semver')
local pathJoin = require('luvi').path.join
local listToMap = require('git').listToMap

local function evalModule(data, name)
  local fn, err = loadstring(data, name)
  if not fn then return nil, err end
  local exports = {}
  local module = { exports = exports }
  setfenv(fn, {
    exports = exports,
  })
  local success, ret = pcall(fn)

  local meta = success and type(ret) == "table" and ret or module.exports
  if not meta then return nil, "Missing exports in " .. name end
  if not meta.name then return nil, "Missing name in package description in " .. name end
  if not meta.version then return nil, "Missing version in package description in " .. name end
  return meta
end

local validKeys = {
  name = "string",
  version = "string",
  private = "boolean", -- Don't allow publishing.
  obsolete = "boolean", -- Hide from search results.
  description = "string",
  keywords = "table", -- list of strings
  tags = "table", -- list of strings
  homepage = "string",
  license = "string",
  licenses = "table", -- table of strings
  author = "table", -- person {name=name, email=email, url=url}
  contributors = "table", -- list of people
  dependencies = "table", -- list of strings
  luvi = "table", -- {flavor=flavor,version=version},
  files = "table",
}

function exports.query(fs, path)
  local packagePath = path
  local stat, data, err
  stat, err = fs.stat(path)
  if stat then
    if stat.type == "directory" then
      packagePath = path .. "/"
      data, err = fs.readFile(pathJoin(path, "package.lua"))
      if err and not err:match("^ENOENT:") then error(err) end
      if not data then
        data, err = fs.readFile(pathJoin(path, "init.lua"))
        if err and not err:match("^ENOENT:") then error(err) end
      end
    else
      data, err = fs.readFile(packagePath)
    end
  elseif err:match("^ENOENT:") then
    packagePath = packagePath .. ".lua"
    data, err = fs.readFile(packagePath)
  end
  if not data then
    return data, err or "Can't find package at " .. path
  end
  local meta = evalModule(data, packagePath)
  local clean = {}
  if not meta then return nil, "No meta found" end
  for key, value in pairs(meta) do
    if type(value) == validKeys[key] then
      clean[key] = value
    end
  end
  return clean, packagePath
end

function exports.queryDb(db, hash)
  local kind, value = db.loadAny(hash)
  if kind == "tag" then
    kind, value = db.loadAny(value.object)
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
