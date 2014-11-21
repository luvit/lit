-- blob
-- tree
-- commit
-- tag

local fs = require('fs')
local msgpack = require('MessagePack')

local encoders = {}
exports.encoders = encoders
local decoders = {}
exports.decoders = decoders


function encoders.blob(blob)
  assert(type(blob) == "string", "blobs must be strings")
  return blob
end

function encoders.tree(tree)
end
