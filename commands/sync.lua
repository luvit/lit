local log = require('../lib/log')
local core = require('../lib/autocore')
local db = core.db

assert(core.config.upstream, "Must have upstream to sync to")
local hashes = {}
local tags = {}
for author in db.authors() do
  for name in db.names(author) do
    local versions = {}
    for version in db.versions(author, name) do
      local match, hash = db.offlineMatch(author, name, version)
      versions[match] = hash
    end
    for version, hash in pairs(versions) do
      local match, newHash = db.match(author, name, version)
      if hash ~= newHash then
        hashes[#hashes + 1] = newHash
        tags[#tags + 1] = author .. "/" .. name .. "/v" .. match
      end
    end
  end
end
log("syncing", table.concat(tags, ", "))
db.fetch(hashes)
