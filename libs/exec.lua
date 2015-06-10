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
