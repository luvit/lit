--[[lit-meta
  name = "creationix/coro-wrapper"
  version = "3.0.0"
  homepage = "https://github.com/luvit/lit/blob/master/deps/coro-wrapper.lua"
  description = "An adapter for applying decoders to coro-streams."
  tags = {"coro", "decoder", "adapter"}
  license = "MIT"
  author = { name = "Tim Caswell" }
]]

local concat = table.concat
local sub = string.sub

-- Merger allows for effecient merging of many chunks.
-- The scan function returns truthy when the chunk contains a useful delimeter
-- Or in other words, when there is enough data to flush to the decoder.
--   merger(read, scan) -> read, updateScan
--     read() -> chunk or nil
--     scan(chunk) -> should_flush
--     updateScan(scan)
local function merger(read, scan)
  local parts = {}

  -- Return a new read function that combines chunks smartly
  return function ()

    while true do
      -- Read the next event from upstream.
      local chunk = read()

      -- We got an EOS (end of stream)
      if not chunk then
        -- If there is nothing left to flush, emit EOS here.
        if #parts == 0 then return end

        -- Flush the buffer
        chunk = concat(parts)
        parts = {}
        return chunk
      end

      -- Accumulate the chunk
      parts[#parts + 1] = chunk

      -- Flush the buffer if scan tells us to.
      if scan(chunk) then
        chunk = concat(parts)
        parts = {}
        return chunk
      end

    end
  end,

  -- This is used to update or disable the scan function.  It's useful for
  -- protocols that change mid-stream (like HTTP upgrades in websockets)
  function (newScan)
    scan = newScan
  end
end

-- Decoder takes in a read function and a decode function and returns a new
-- read function that emits decoded events.  When decode returns `nil` it means
-- that it needs more data before it can parse.  The index output in decode is
-- the index to start the next decode.  If output index if nil it means nothing
-- is leftover and next decode starts fresh.
--   decoder(read, decode) -> read, updateDecode
--     read() -> chunk or nil
--     decode(chunk, index) -> nil or (data, index)
--     updateDecode(Decode)
local function decoder(read, decode)
  local buffer, index
  return function ()

    while true do

      -- If we have data, lets try to decode it
      if buffer then
        local item, newIndex = decode(buffer, index)
        -- There was enough data to emit an event!
        if item then
          if newIndex then
            -- There was leftover data
            index = newIndex
          else
            -- There was no leftover data
            buffer = nil
          end
          -- Emit the event
          return item
        end
      end

      -- There wasn't enough data to decode, lets get more data.
      local chunk = read()
      if buffer then
        -- If we had leftover data in the old buffer, trim it down.
        if index > 1 then
          buffer = sub(buffer, index)
          index = 1
        end
        -- Concatenate the chunk with the old data
        buffer = buffer .. chunk
      else
        -- If there was no leftover data, set new data in the buffer
        buffer = chunk
        index = 1
      end

    end
  end,
  function (newDecode)
    decode = newDecode
  end
end

local function encoder(write, encode)
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
  merger = merger,
  decoder = decoder,
  encoder = encoder,
}
