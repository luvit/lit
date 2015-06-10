--[[

Copyright 2014-2015 The Luvit Authors. All Rights Reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS-IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

--]]

local pathJoin = require('luvi').path.join
local rules = require('rules')
local isAllowed = rules.isAllowed
local compileFilter = rules.compileFilter
local modes = require('git').modes

-- Import a fs path into the database
return function (db, fs, path, rules, nativeOnly)
  if nativeOnly == nil then nativeOnly = false end
  local filters = {}
  if rules then
    filters[#filters + 1] = compileFilter(path, rules, nativeOnly)
  end

  local importEntry, importTree

  function importEntry(path, stat)
    if stat.type == "directory" then
      local hash = importTree(path)
      if not hash then return end
      return modes.tree, hash
    end
    if stat.type == "file" then
      if not stat.mode then
        stat = fs.stat(path)
      end
      local mode = bit.band(stat.mode, 73) > 0 and modes.exec or modes.file
      return mode, db.saveAs("blob", assert(fs.readFile(path)))
    end
    if stat.type == "link" then
      return modes.sym, db.saveAs("blob", assert(fs.readlink(path)))
    end
    error("Unsupported type at " .. path .. ": " .. tostring(stat.type))
  end

  function importTree(path)
    assert(type(fs) == "table")

    local items = {}
    local meta = fs.readFile(pathJoin(path, "package.lua"))
    if meta then meta = loadstring(meta)() end
    if meta and meta.files then
      filters[#filters + 1] = compileFilter(path, meta.files, nativeOnly)
    end

    for entry in assert(fs.scandir(path)) do
      local fullPath = pathJoin(path, entry.name)
      entry.type = entry.type or fs.stat(fullPath).type
      if isAllowed(fullPath, entry, filters) then
        entry.mode, entry.hash = importEntry(fullPath, entry)
        if entry.hash then
          items[#items + 1] = entry
        end
      end
    end
    return #items > 0 and db.saveAs("tree", items)
  end

  local mode, hash = importEntry(path, assert(fs.stat(path)))
  if not hash then return end
  return modes.toType(mode), hash
end

