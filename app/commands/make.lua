local log = require('../lib/log')
local config = require('../lib/config')
local uv = require('uv')
local pathJoin = require('luvi').path.join
local db = config.db
local readPackageFs = require('../lib/read-package').readFs
local fs = require('coro-fs')
local git = require('git')
local parseDeps = require('../lib/parse-deps')
local miniz = require('miniz')

local function importGraph(files, root, hash)
  local function walk(path, hash)
    local raw = assert(db.load(hash))
    local kind, data = git.deframe(raw)
    data = git.decoders[kind](data)
    if kind == "tag" then
      return walk(path, data.object)
    elseif kind == "tree" then
      files["modules/" .. path .. "/"] = ""
      for i = 1, #data do
        local entry = data[i]
        local newPath = #path > 0 and path .. "/" .. entry.name or entry.name
        walk(newPath, entry.hash)
      end
    else
      if path == root then path = path .. ".lua" end
      files["modules/" .. path] = data
    end
  end
  walk(root, hash)
end

local ignores = {
  [".git"] = true,
}

local function importFolder(fs, files, path)
  for entry in fs.scandir(path) do
    if not ignores[entry.name] then
      local newPath = #path > 0 and path .. "/" ..entry.name or entry.name
      if entry.type == "directory" then
        log("importing directory", newPath)
        files[newPath .. "/"] = ""
        importFolder(fs, files, newPath)
      elseif entry.type == "file" then
        -- log("importing file", newPath)
        local data = assert(fs.readFile(newPath))
        files[newPath] = data
      end
    end
  end
end

local function makeApp(path)
  local meta
  meta, path = assert(readPackageFs(path))

  local fs = fs.chroot(pathJoin(path, ".."))
  if not fs.readFile("main.lua") then
    error("Missing main.lua in app: " .. path)
  end
  meta.dependencies = meta.dependencies or {}
  log("processing deps", #meta.dependencies)
  local deps = parseDeps(meta.dependencies)

  local target = pathJoin(uv.cwd(), meta.target or meta.name)
  log("creating binary", target)
  local fd = assert(uv.fs_open(target, "w", 511)) -- 0777

  -- Copy base binary
  local binSize
  do
    local source = uv.exepath()

    local reader = miniz.new_reader(source)
    if reader then
      -- If contains a zip, find where the zip starts
      binSize = reader:get_offset()
    else
      -- Otherwise just read the file size
      binSize = uv.fs_stat(source).size
    end
    local fd2 = assert(uv.fs_open(source, "r", 384)) -- 0600
    log("copying binary prefix", binSize .. " bytes")
    uv.fs_sendfile(fd, fd2, 0, binSize)
    uv.fs_close(fd2)
  end

  local files = {}
  -- Import all the dependencies.
  files["modules/"] = ""
  for name, dep in pairs(deps) do
    log("installing dep", name .. "@" .. dep.version)
    importGraph(files, name, dep.hash)
  end

  -- import the local files on top
  importFolder(fs, files, "")

  local keys = {}
  for path in pairs(files) do
    keys[#keys + 1] = path
  end

  table.sort(keys)

  local writer = miniz.new_writer()
  for i = 1, #keys do
    local key = keys[i]
    local data = files[key]
    writer:add(key, data, #data > 0 and 9 or nil)
  end
  uv.fs_write(fd, writer:finalize(), binSize)
  uv.fs_close(fd)
  log("done building", target)

end

local cwd = uv.cwd()
if #args > 1 then
  for i = 2, #args do
    makeApp(pathJoin(cwd, args[i]))
  end
else
  makeApp(cwd)
end
