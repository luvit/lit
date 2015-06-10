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

local import = require('import')
local modes = require('git').modes
local export = require('export')
local pathJoin = require('luvi').path.join

-- Given a db tree and a set of dependencies, create a new tree with the deps
-- folder synthisized from the deps list.

function exports.toDb(db, rootHash, deps)
  local tree = db.loadAs("tree", rootHash)
  local depsTree = {}
  for alias, meta in pairs(deps) do
    local entry = {}
    local kind, hash
    if meta.hash then
      hash = meta.hash
      kind = meta.kind
    else
      kind, hash = import(db, meta.fs, meta.path, nil, true)
    end
    entry.mode = assert(modes[kind])
    entry.hash = hash
    if kind == "blob" then
      entry.name = alias .. ".lua"
    else
      entry.name = alias
    end

    depsTree[#depsTree + 1] = entry
  end
  tree[#tree + 1] = {
    name = "deps",
    mode = modes.tree,
    hash = db.saveAs("tree", depsTree)
  }
  return db.saveAs("tree", tree)
end

function exports.toFs(fs, rootPath, deps)
  for alias, meta in pairs(deps) do
    if meta.hash then
      local path = pathJoin(rootPath, "deps", alias)
      if meta.kind == "blob" then
        path = path .. ".lua"
      end
      export(meta.db, meta.hash, fs, path)
    end
  end
end
