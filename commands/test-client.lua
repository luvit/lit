local config = require('../lib/config')
local db = config.db

-- assert(config.upstream, "Must have upstream to test network")

print("Looking up latest version of 'creationix/git'")

db.match("creationix/git", "1")
local version, hash = db.match("creationix/git")

p(version, hash)

local tag = db.loadAs("tag", hash)
p(tag)
local object = db.loadAs(tag.type, tag.object)
p(object)

-- local top = loadAs(tag.type, tag.object)
-- p(top)
-- storage.write()
