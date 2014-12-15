exports.name = "creationix/prompt"
exports.version = "0.1.0"

local readLine = require('readline').readLine

-- Wrapper around readline to provide a nice blocking version for coroutines
return function (message, default)
  local thread = coroutine.running()

  message = message .. ": "
  if default then
    message = message .. "(" .. default .. ") "
  end

  local value
  repeat
    readLine(message, function (err, line, reason)
      if err then
        return assert(coroutine.resume(thread, nil, err))
      end
      return assert(coroutine.resume(thread, line, reason))
    end)
    value = assert(coroutine.yield())
    if default and #value == 0 then
      value = default
    end
  until #value > 0
  return value
end
