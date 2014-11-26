local uv = require('uv')
local fs = exports

local function noop() end

local function makeCallback()
  local thread = coroutine.running()
  return function (...)
    return assert(coroutine.resume(thread, ...))
  end
end

function fs.mkdir(path, mode)
  uv.fs_mkdir(path, mode or 511, makeCallback())
  return coroutine.yield()
end

function fs.open(path, flags, mode)
  uv.fs_open(path, flags or "r", mode or 438, makeCallback())
  return coroutine.yield()
end
function fs.stat(path)
  uv.fs_stat(path, makeCallback())
  return coroutine.yield()
end
function fs.lstat(path)
  uv.fs_lstat(path, makeCallback())
  return coroutine.yield()
end
function fs.readlink(path)
  uv.fs_readlink(path, makeCallback())
  return coroutine.yield()
end
function fs.fstat(fd)
  uv.fs_fstat(fd, makeCallback())
  return coroutine.yield()
end
function fs.read(fd, length, offset)
  uv.fs_read(fd, length, offset or -1, makeCallback())
  return coroutine.yield()
end
function fs.write(fd, data, offset)
  uv.fs_write(fd, data, offset or -1, makeCallback())
  return coroutine.yield()
end
function fs.close(fd)
  uv.fs_close(fd, makeCallback())
  return coroutine.yield()
end

function fs.scandir(path, iter)
  local callback = makeCallback()
  uv.fs_scandir(path, callback)
  local err, req = coroutine.yield()
  if err then return err end
  while true do
    local entry = uv.fs_scandir_next(req)
    if not entry then return end
    iter(entry)
  end
end

function fs.readFile(path)
  local callback = makeCallback()
  local fd, stat, data, err
  uv.fs_open(path, "r", 384, callback)
  err, fd = coroutine.yield()
  if err then return err end
  uv.fs_fstat(fd, callback)
  err, stat = coroutine.yield()
  if stat then
    uv.fs_read(fd, stat.size, 0, callback)
    err, data = coroutine.yield()
  end
  uv.fs_close(fd, noop)
  return err, data
end

function fs.readFile2(path)
  local callback = makeCallback()
  local parts = {}
  local fd, chunk, err
  uv.fs_open(path, "r", 384, callback)
  err, fd = coroutine.yield()
  if err then return err end
  repeat
    uv.fs_read(fd, 4096, -1, callback)
    err, chunk = coroutine.yield()
    if err then break end
    if #chunk > 0 then
      parts[#parts + 1] = chunk
    end
  until #chunk < 4096
  uv.fs_close(fd, noop)
  return err, table.concat(parts)
end

function fs.writeFile(path, data)
  local callback = makeCallback()
  local fd, err
  uv.fs_open(path, "w", 438, callback)
  err, fd = coroutine.yield()
  if err then return err end
  uv.fs_write(fd, data, 0, callback)
  err = coroutine.yield()
  uv.fs_close(fd, noop)
  return err
end
