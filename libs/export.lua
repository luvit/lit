local pathJoin = require('luvi').path.join
local modes = require('git').modes

-- Export a db hash to the fs at path.

-- db is a git db instance
-- fs is a coro-fs instance
return function (db, rootHash, fs, rootPath)
  local function exportEntry(path, hash, mode)
    local kind, value = db.loadAny(hash)
    if kind == "tag" then
      return exportEntry(path, value.object)
    end
    if not mode then
      mode = modes[kind]
    else
      assert(modes.toType(mode) == kind, "Git kind mismatch")
    end
    if mode == modes.tree then
      for i = 1, #value do
        local entry = value[i]
        exportEntry(pathJoin(path, entry.name), entry.hash, entry.mode)
      end
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
    return kind
  end

  return exportEntry(rootPath, rootHash)
end
