local config = require('../lib/config')

local git = require('creationix/git')

assert(config.upstream, "Must have upstream to test network")

local function loadAs(kind, hash, raw)
  local value, actualKind = git.deframe(storage:load(hash), raw)
  assert(kind == actualKind)
  return value
end


local version, hash = storage:match("creationix/git")
p(version, hash)
local tag = loadAs("tag", hash)
p(tag)
local top = loadAs(tag.type, tag.object)
p(top)
storage.write()
