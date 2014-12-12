local readLine = require('readline').readLine

-- Wrapper around readline to provide a nice blocking version for coroutines
return function (message)
  local thread = coroutine.running()
  readLine(message, function (err, line, reason)
    if err then
      return assert(coroutine.resume(thread, nil, err))
    end
    return assert(coroutine.resume(thread, line, reason))
  end)
  return coroutine.yield()
end
