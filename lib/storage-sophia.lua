local Sophia = require('./sophia.so')
local digest = require('openssl').digest.digest
local log = require('./log')
local hexToBin = require('creationix/hex-bin').hexToBin
local binToHex = require('creationix/hex-bin').binToHex

local function escape(c)
  return "%" .. c
end

return function (dir)

  local storage = {}

  local env = Sophia.env()
  env:ctl("dir", dir .. "-objects")
  local object_db = assert(env:open())
  env = Sophia.env()
  env:ctl("dir", dir .. "-tags")
  local tag_db = assert(env:open())

  --[[
  storage.has(hash) -> boolean
  ----------------------------

  Quick check to see if a hash is in the database already.
  ]]
  function storage.has(hash)
    error("TODO: Implement has")
  end

  --[[
  storage.load(hash) -> data
  --------------------------

  Load raw data by hash, verify hash before returning.
  ]]
  function storage.load(hash)
    local key = hexToBin(hash)
    local value, err = object_db:get(key)
    if err then return nil, err end
    if not value then return end
    assert(hash == digest("sha1", value), "hash mismatch")
    return value
  end

  --[[
  storage.save(data) -> hash
  --------------------------

  Save raw data and return hash
  ]]--
  function storage.save(data)
    local hash = digest("sha1", data)
    local key = hexToBin(hash)
    if object_db:get(key) then
      return hash
    end
    log("save", hash)
    local success, err = object_db:set(key, data)
    if success then
      return hash
    end
    return nil, err
  end

  --[[
  storage.read(tag) -> hash
  -------------------------

  Given a full tag (name and version), return the hash or nil for no such match.
  ]]--
  function storage.read(tag)
    local raw = tag_db:get(tag)
    return raw and binToHex(raw)
  end

  --[[
  storage.write(tag, hash)
  ------------------------

  Write the hash for a full tag (name and version). Fails if the tag already
  exists.
  ]]--
  function storage.write(tag, hash)
    local value = hexToBin(hash)
    if tag_db:get(tag) == value then return end
    log("write", tag)
    return tag_db:set(tag, value)
  end

  --[[
  storage.versions(name) -> iterator<version>
  -------------------------------------------

  Given a package name, return an iterator of versions or nil if no such
  package.
  ]]
  function storage.versions(name)
    local pattern = "^" .. name:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", escape) .. "/[^/%d]*(%d+%.%d+%.%d+[^/]*)$"
    local iter, scope, key = tag_db:cursor()
    return function ()
      repeat
        local tag
        tag, key = iter(scope, key)
        if tag then
          local version = string.match(tag, pattern)
          if version then return version end
        end
      until not tag
    end
  end

  return storage

end




-- function Storage:begin()
--   log("transaction", "begin")
--   self.object_db:begin()
--   self.tag_db:begin()
-- end

-- function Storage:commit()
--   log("transaction", "commit", "success")
--   self.object_db:commit()
--   self.tag_db:commit()
-- end

-- function Storage:rollback()
--   log("transaction", "rollback", "failure")
--   self.object_db:rollback()
--   self.tag_db:rollback()
-- end

-- return function (dir)
--   return Storage:new(dir)
-- end
