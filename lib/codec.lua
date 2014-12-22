local wrapStream = require('creationix/coro-channel').wrapStream
local encoder = require('../lib/encoder')
local decoder = require('../lib/decoder')

return function (isServer, client)
  local read, write = wrapStream(client)
  local decode = decoder(isServer)
  local buffer = ""
  -- read
  return function ()
    while true do
      if #buffer > 0 then
        local extra, command, data = decode(buffer)
        if extra then
          buffer = extra
          return command, data
        end
      end
      local chunk = read()
      p("INPUT", chunk)
      if not chunk then return end
      buffer = buffer .. chunk
    end
  end,
  function (command, data)
    if not command then
      return write()
    end
    local encode = encoder[command]
    if not encode then
      error("Unknown encoding: " .. command)
    end
    local encoded = encode(data)
    p("OUTPUT", encoded)
    return write(encoded)
  end
end
