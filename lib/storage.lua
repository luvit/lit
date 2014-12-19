local config = require('./config')
local upstream
local storage = require('./storage-' .. config.storage)(config.database)
if config.upstream then
  upstream = require('./storage-remote')(config.upstream)
else
  return storage
end

local db = {}
db.save = storage.save

-- Try to load locally first, if it fails, load from remote
-- and cache locally.
function db.load(_, hash)
  local data, err = storage:load(hash)
  if data or err then return data, err end
  data, err = upstream:load(hash)
  if not data then return data, err end
  assert(storage:save(data) == hash)
  return data
end

db.versions = storage.versions

function db.read(_, tag)
  local hash, err = storage:read(tag)
  if hash or err then return hash, err end
  hash, err = upstream:read(tag)
  if not hash then return hash, err end
  assert(storage:write(tag, hash))
  return hash
end

db.write = storage.write
