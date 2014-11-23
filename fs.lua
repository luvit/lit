local uv = require('uv')
local fs = exports

function fs.mkdir(path)
  local thread = coroutine.running()
  uv.fs_mkdir(path, function (err)
    return assert(coroutine.resume(thread, err))
  end)
  return coroutine.yield()
end

function fs.open(path, flags, mode)
  local thread = coroutine.running()
  uv.fs_open(path, flags, mode, function (err, fd)
    return assert(coroutine.resume(thread, err, fd))
  end)
  return coroutine.yield()
end
function fs.fstat(fd)
  local thread = coroutine.running()
  uv.fs_fstat(fd, function (err, stat)
    return assert(coroutine.resume(thread, err, stat))
  end)
  return coroutine.yield()
end
function fs.read(fd, length, offset)
  local thread = coroutine.running()
  uv.fs_read(fd, length, offset, function (err, data)
    return assert(coroutine.resume(thread, err, data))
  end)
  return coroutine.yield()
end
function fs.write(fd, data, offset)
  local thread = coroutine.running()
  uv.fs_write(fd, data, offset, function (err, written)
    return assert(coroutine.resume(thread, err, written))
  end)
  return coroutine.yield()
end
function fs.close(fd)
  local thread = coroutine.running()
  uv.fs_close(fd, function (err)
    return assert(coroutine.resume(thread, err))
  end)
  return coroutine.yield()
end
