local import = require('import')
local modes = require('git').modes

-- Given a db tree and a set of dependencies, create a new tree with the deps
-- folder synthisized from the deps list.

return function (db, rootHash, deps)
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
    entry.mode = modes[kind]
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
