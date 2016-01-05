--[[lit-meta
  name = "creationix/coro-wrapper"
  version = "2.0.0"
  homepage = "https://github.com/luvit/lit/blob/master/deps/coro-wrapper.lua"
  description = "An adapter for applying decoders to coro-streams."
  tags = {"coro", "decoder", "adapter"}
  license = "MIT"
  author = { name = "Tim Caswell" }
]]

local function reader(read, decode)
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

local function writer(write, encode)
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

return {
  reader = reader,
  writer = writer,
}
