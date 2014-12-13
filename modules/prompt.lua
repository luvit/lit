local Editor = require('readline').Editor

-- Wrapper around readline to provide a nice blocking version for coroutines
return function (message, value)
  local thread = coroutine.running()
  local editor = Editor.new()
  editor:readLine(message, function (err, line, reason)
    if err then
      return assert(coroutine.resume(thread, nil, err))
    end
    return assert(coroutine.resume(thread, line, reason))
  end)
  if value then
    editor.line = value
    if editor.position > #value + 1 then
      editor.position = #value + 1
    end
    editor.history:updateLastLine(editor.line)
    editor:refreshLine()
  end
  return coroutine.yield()
end
