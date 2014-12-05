local Object = require('core').Object
local Sophia = require('sophia.so')
local digest = require('openssl').digest.digest

local Storage = Object:extend()

function Storage:initialize(dir)
  local env = Sophia.env()
  self.env = env
  env:ctl("dir", dir)
  self.db = assert(env:open())
  self.dir = dir
end

-- Save a binary blob to disk, returns the sha1 hash of the value
-- value is a string.
function Storage:save(value)
  local hash = digest("sha1", value)
  if self.db:get(hash) then
    return hash
  end
  local success, err = self.db:set(hash, value)
  if success then
    return hash
  end
  return nil, err
end

function Storage:load(hash)
  local value, err = self.db:get(hash)
  if err then return nil, err end
  if not value then return end
  if hash ~= digest("sha1", value) then
    return nil, "value doesn't match hash: " .. hash
  end
  return value
end

function Storage:read(key)
  return self.db:get(key)
end

function Storage:write(key, value)
  return self.db:set(key, value)
end

function Storage:begin()
  return self.db:begin()
end

function Storage:commit()
  return self.db:commit()
end

function Storage:rollback()
  return self.db:rollback()
end

return Storage
