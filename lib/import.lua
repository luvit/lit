local git = require('creationix/git')
local fs = require('creationix/coro-fs')
local modes = git.modes
local pathJoin = require('luvi').path.join
local log = require('./log')

local function importBlob(db, path)
  log("importing blob", path)
  return db.saveAs("blob", assert(fs.readFile(path)))
end
exports.blob = importBlob

local function importLink(db, path)
  log("importing link", path)
  return db.saveAs("blob", fs.readlink(path))
end
exports.link = importLink

local function importTree(db, path)
  log("importing tree", path)
  local items = {}
  for entry in fs.scandir(path) do
    if string.sub(entry.name, 1, 1) ~= '.' then
      local fullPath = pathJoin(path, entry.name)
      local item = { name = entry.name }
      if entry.type == "directory" then
        item.mode = modes.tree
        item.hash = importTree(db, fullPath)
      elseif entry.type == "file" then
        local stat = fs.stat(fullPath)
        if bit.band(stat.mode, 73) > 0 then
          item.mode = modes.exec
        else
          item.mode = modes.file
        end
        item.hash = importBlob(db, fullPath)
      elseif entry.type == "link" then
        item.mode = modes.sym
        item.hash = importLink(db, fullPath)
      else
        p(path, entry)
        error("Unsupported type " .. entry.type)
      end
      items[#items + 1] = item
    end
  end
  return db.saveAs("tree", items)
end
exports.tree = importTree
