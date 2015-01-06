local git = require('creationix/git')
local log = require('./log')
local modes = git.modes
local pathJoin = require('luvi').path.join
local fs = require('creationix/coro-fs')

local function exportBlob(db, path, hash, mode)
  log("export blob", path, "string")
  mode = mode or modes.file
  -- TODO: preserve exec attr on files
  local data = assert(db.loadAs("blob", hash))
  local fd, success, err
  fd, err = fs.open(path, "w", mode)
  if not fd then
    if string.match(err, "^ENOENT:") then
      fs.mkdirp(pathJoin(path, ".."))
      fd, err = fs.open(path, "w")
    end
    assert(fd, err)
  end
  success, err = fs.write(fd, data, 0)
  fs.close(fd)
  return assert(success, err)
end
exports.blob = exportBlob

local function exportLink(db, path, hash)
  log("export link", path, "string")
  return fs.symlink(path, db.loadAs("blob", hash))
end
exports.link = exportLink

local function exportTree(db, path, hash)
  log("export tree", path, "string")
  fs.mkdirp(path)
  local tree = db.loadAs("tree", hash)
  for i = 1, #tree do
    local entry = tree[i]
    local exporter = modes.isFile(entry.mode) and exportBlob
                  or entry.mode == modes.sym and exportLink
                  or entry.mode == modes.tree and exportTree
                  or nil
    exporter(db, pathJoin(path, entry.name), entry.hash, entry.mode)
  end
end
exports.tree = exportTree
