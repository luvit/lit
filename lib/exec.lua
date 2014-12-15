
local uv = require('uv')
return function (command, ...)
  local args = {...}
  local thread = coroutine.running()
  local pout = uv.new_pipe(false)
  local perr = uv.new_pipe(false)
  local stdout, stderr, code, signal
  local child
  local done = false
  local function check()
    if done then return end
    if stdout and stderr and (code or signal) then
      done = true
      return assert(coroutine.resume(thread, stdout, stderr, code, signal))
    end
  end
  local function fail(err)
    if done then return end
    done = true
    return assert(coroutine.resume(thread, nil, err))
  end
  child = uv.spawn(command, {
    args = args,
    stdio = {nil, pout, perr}
  }, function (c, s)
    code = c
    signal = s
    child:close()
    check()
  end)
  do
    local data = ""
    pout:read_start(function (err, chunk)
      if err then return fail(err) end
      if chunk then
        data = data .. tostring(chunk)
      else
        stdout = data
        pout:read_stop()
        pout:close()
        return check()
      end
    end)
  end
  do
    local data = ""
    perr:read_start(function (err, chunk)
      if err then return fail(err) end
      if chunk then
        data = data .. tostring(chunk)
      else
        stderr = data
        perr:read_stop()
        perr:close()
        return check()
      end
    end)
  end
  return coroutine.yield()
end
