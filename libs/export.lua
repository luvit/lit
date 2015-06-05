local pathJoin = require('luvi').path.join
local filterTree = require('rules').filterTree
local modes = require('git').modes

-- Export a db hash to the fs at path.

-- db is a git db instance
-- fs is a coro-fs instance
return function (db, hash, fs, path, rules, nativeOnly)
  if nativeOnly == nil then nativeOnly = true end
  local kind, value = db.loadAny(hash)
  if not kind then error(value or "No such hash") end

  if kind == "tree" then
    hash = filterTree(db, path, hash, rules, nativeOnly)
    value = db.loadAs("tree", hash)
  end

  local exportEntry, exportTree

  function exportEntry(path, mode, value)
    if mode == modes.tree then
      exportTree(path, value)
    elseif mode == modes.sym then
      local success, err = fs.symlink(value, path)
      if not success and err:match("^ENOENT:") then
        assert(fs.mkdirp(pathJoin(path, "..")))
        assert(fs.symlink(value, path))
      end
    elseif modes.isFile(mode) then
      local success, err = fs.writeFile(path, value)
      if not success and err:match("^ENOENT:") then
        assert(fs.mkdirp(pathJoin(path, "..")))
        assert(fs.writeFile(path, value))
      end
      assert(fs.chmod(path, mode))
    else
      error("Unsupported mode at " .. path .. ": " .. mode)
    end
  end

  function exportTree(path, tree)

    assert(fs.mkdirp(path))
    for i = 1, #tree do
      local entry = tree[i]
      local fullPath = pathJoin(path, entry.name)
      local kind, value = db.loadAny(entry.hash)
      assert(modes.toType(entry.mode) == kind, "Git kind mismatch")
      exportEntry(fullPath, entry.mode, value)
    end
  end


  exportEntry(path, kind == "tree" and modes.tree or modes.blob, value)
  return kind
end
