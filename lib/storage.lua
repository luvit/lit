local config = require('./config')
local upstream
local storage = require('./storage-' .. config.storage)(config.database)
if config.upstream then
  upstream = require('./storage-remote')(config.upstream)
else
  return storage
end

local combined = {}
combined.save = storage.save

-- Try to load locally first, if it fails, load from remote
-- and cache locally.
function combined.load(_, hash)
  local data, err = storage:load(hash)
  if data or err then return data, err end
  data, err = upstream:load(hash)
  if not data then return data, err end
  assert(storage:save(data) == hash)
  return data
end

combined.versions = upstream.versions

function combined.read(_, tag)
  local hash, err = storage:read(tag)
  if hash or err then return hash, err end
  return upstream:read(tag)
end

combined.write = storage.write
