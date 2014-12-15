local Object = require('core').Object
local Sophia = require('sophia.so')
local digest = require('openssl').digest.digest
local log = require('./lit-log')
local hexToBin = require('./hex-to-bin')
local binToHex = require('./bin-to-hex')

local Storage = Object:extend()

function Storage:initialize(dir)
  local env = Sophia.env()
  env:ctl("dir", dir .. "-objects")
  self.object_db = assert(env:open())
  env = Sophia.env()
  env:ctl("dir", dir .. "-tags")
  self.tag_db = assert(env:open())
  self.dir = dir
end

-- Save a binary blob to disk, returns the sha1 hash of the value
-- value is a string.
function Storage:save(value)
  local hash = digest("sha1", value)
  local key = hexToBin(hash)
  if self.object_db:get(key) then
    return hash
  end
  log("save", hash)
  local success, err = self.object_db:set(key, value)
  if success then
    return hash
  end
  return nil, err
end

function Storage:load(hash)
  local key = hexToBin(hash)
  local value, err = self.object_db:get(key)
  if err then return nil, err end
  if not value then return end
  if hash ~= digest("sha1", value) then
    return nil, "value doesn't match hash: " .. hash
  end
  return value
end

local function escape(c)
  return "%" .. c
end

function Storage:versions(name)
  local results = {}
  local pattern = "^" .. name:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", escape) .. "/[^/%d]*(%d+%.%d+%.%d+[^/]*)$"
  for tag in self.tag_db:cursor() do
    local version = string.match(tag, pattern)
    if version then
      results[#results + 1] = version
    end
  end
  return results
end

function Storage:read(key)
  return binToHex(self.tag_db:get(key))
end

function Storage:write(key, hash)
  local value = hexToBin(hash)
  if self.tag_db:get(key) == value then return end
  log("write", key)
  return self.tag_db:set(key, value)
end

function Storage:begin()
  log("transaction", "begin")
  self.object_db:begin()
  self.tag_db:begin()
end

function Storage:commit()
  log("transaction", "commit", "success")
  self.object_db:commit()
  self.tag_db:commit()
end

function Storage:rollback()
  log("transaction", "rollback", "failure")
  self.object_db:rollback()
  self.tag_db:rollback()
end

return function (dir)
  return Storage:new(dir)
end
