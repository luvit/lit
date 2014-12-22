local config = require('../lib/config')

local db = config.db

assert(config.upstream, "Must have upstream to test network")

print("Looking up latest version of 'creationix/git'")
local version, hash = db.match("creationix/git")
p(version, hash)

local tag = db.loadAs("tag", hash)
-- local tag = loadAs("tag", hash)
-- p(tag)
-- local top = loadAs(tag.type, tag.object)
-- p(top)
-- storage.write()
