exports.name = "creationix/prompt"
exports.version = "1.0.3-2"
exports.dependencies = {
  "luvit/readline@1.1.1"
}
exports.homepage = "https://github.com/luvit/lit/blob/master/deps/prompt.lua"
exports.description = "A simple wrapper around readline for quick terminal prompts."
exports.tags = {"tty", "prompt"}
exports.license = "MIT"
exports.author = { name = "Tim Caswell" }

local readLine = require('readline').readLine

return function (options)
  -- Wrapper around readline to provide a nice blocking version for coroutines
  return function (message, default)
    local thread = coroutine.running()

    message = message .. ": "
    if default then
      message = message .. "(" .. default .. ") "
    end

    local value
    repeat
      readLine(message, options, function (err, line, reason)
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
end
