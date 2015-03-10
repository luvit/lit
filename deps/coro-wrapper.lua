exports.name = "creationix/coro-wrapper"
exports.version = "1.0.0"

function exports.reader(read, decode)
  local buffer = ""
  return function ()
    while true do
      local item, extra = decode(buffer)
      if item then
        buffer = extra
        return item
      end
      local chunk = read()
      if not chunk then return end
      buffer = buffer .. chunk
    end
  end,
  function (newDecode)
    decode = newDecode
  end
end

function exports.writer(write, encode)
  return function (item)
    if not item then
      return write()
    end
    return write(encode(item))
  end,
  function (newEncode)
    encode = newEncode
  end
end
