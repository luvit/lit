--[[

Copyright 2014-2016 The Luvit Authors. All Rights Reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS-IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

]]

local hasLuvi, luvi = pcall(require, 'luvi')
if not hasLuvi then
  return error('luvit-loader does not support non-luvi environments')
end
local uv = require('uv')

local loadstring = loadstring or load
local bundle = luvi.bundle
local pathJoin = luvi.path.join
local cwd = uv.cwd()

local moduleDirs = {"deps", "libs"}

--- Detects if the given path is a bundle path and returns the path part only,
--- otherwise returns the given path unmodified.
---@return boolean isBundle
---@return string path
---@nodiscard
local function stripBundle(path)
  local bundleMatch, stripped = path:match('^(@?bundle:)(.*)')
  if bundleMatch then
    return true, stripped
  else
    return false, path
  end
end

--- Load a module using luvi's bundle. 
--- The module path must not prefix `bundle:`.
---@return any module
---@nodiscard
local function loadBundle(path)
  local key = 'bundle:' .. path -- differentiate bundled modules from others
  if package.loaded[key] then
    return package.loaded[key]
  end
  local code = bundle.readfile(path)
  local module = assert(loadstring(code, key))(key)
  package.loaded[key] = module
  return module
end

--- Load a module using loadfile on the real filesystem.
---@return any module
---@nodiscard
local function loadFile(path)
  local realPath = uv.fs_realpath(path)
  if package.loaded[realPath] then
    return package.loaded[realPath]
  end
  local module = assert(loadfile(realPath))(realPath)
  package.loaded[realPath] = module
  return module
end

--- A Lua 5.2 style package loader, accepts the module name and its full path.
---@param name string
---@param path string
---@return any module
---@nodiscard
local function loader(name, path)
  local useBundle, stripped = stripBundle(path)
  if useBundle then
    return loadBundle(stripped)
  else
    return loadFile(path)
  end
end

--- Attempt to search path for a module.
--- Returns the full path to the found module, or nil + errors.
---@return string? foundModule
---@return string? errors
---@nodiscard
local function searchPath(path, useBundle)
  local prefix = useBundle and "bundle:" or ""
  local fileStat = useBundle and bundle.stat or uv.fs_stat
  local errors = {}

  -- is it a full path to a file module?
  local newPath = path
  local stat = fileStat(newPath)
  if stat and stat.type == "file" then
    return newPath
  end
  errors[#errors + 1] = "\n\tno file '" .. prefix .. newPath .. "'"

  -- is it a path to a Lua file module?
  newPath = path .. ".lua"
  stat = fileStat(newPath)
  if stat and stat.type == "file" then
    return newPath
  end
  errors[#errors + 1] = "\n\tno file '" .. prefix .. newPath .. "'"

  -- is it a path to a directory with init.lua?
  newPath = pathJoin(path, "init.lua")
  stat = fileStat(newPath)
  if stat and stat.type == "file" then
    return newPath
  end
  errors[#errors + 1] = "\n\tno file '" .. prefix .. newPath .. "'"

  -- we couldn't find anything
  return nil, table.concat(errors)
end

-- Recursively search for a module in deps/libs `moduleDirs` directories
-- until we reach the filesystem root, `../deps`, `../../deps`, etc.
---@param dir string # the search starting position
---@param name string
---@param useBundle boolean?
---@return string? path
---@return string? error
---@nodiscard
local function searchModule(dir, name, useBundle)
  local errors = {}
  local res, err
  while true do
    for _, v in ipairs(moduleDirs) do
      res, err = searchPath(pathJoin(dir, v, name), useBundle)
      if res then
        return res
      end
      errors[#errors + 1] = err
    end
    if dir == pathJoin(dir, "..") then
      return nil, table.concat(errors)
    end
    dir = pathJoin(dir, "..")
  end
end

--- A Lua 5.2 style package searcher that supports Luvit's require paths and luvi's bundles.
---@param name string
---@return fun(name: string, path: string) | nil loader
---@return string pathOrError
---@nodiscard
local function searcher(name)
  -- Find the caller.
  -- Loops past any C functions to get to the real caller,
  -- to avoid pcall(require, "path") getting "=C" as the source.
  local level, caller = 3, nil
  repeat
    caller = debug.getinfo(level, "S").source
    level = level + 1
  until caller ~= "=[C]"
  local useBundle, strippedCaller = stripBundle(caller)

  -- Get the directory relative to the caller
  local dir = ''
  if useBundle then
    dir = pathJoin(strippedCaller, "..")
  elseif string.sub(caller, 1, 1) == "@" then
    dir = pathJoin(cwd, caller:sub(2), "..")
  end

  -- Find the module's full path
  local fullPath, err
  if string.sub(name, 1, 1) == "." then
    -- Relative require
    fullPath, err = searchPath(pathJoin(dir, name), useBundle)
  else
    -- Module require
    fullPath, err = searchModule(dir, name, useBundle)
  end
  if not fullPath then
    return nil, err or 'Module could not be found'
  end

  if useBundle then
    if bundle.stat(fullPath) then
      return loader, 'bundle:' .. fullPath
    end
  else
    if uv.fs_access(fullPath, 'r') then
      return loader, fullPath
    end
  end
  return nil, 'Module was found but could not be accessed: ' .. tostring(fullPath)
end

-- Register as a normal lua package searcher/loader.
-- We insert the loader right after the default preload loader for caching.
if package.loaders then
  -- Combine the searcher and loader into one function for Lua 5.1 compat
  table.insert(package.loaders, 2, function (path)
    local loader_fn, loader_data = searcher(path)
    if type(loader_fn) == "function" then
      return function(name)
        return loader_fn(name, loader_data)
      end
    else
      return loader_fn
    end
  end)
else
  table.insert(package.searchers, 2, searcher)
end
