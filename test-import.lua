local GitStorage = require("storage/fs")
local SophiaStorage = require("storage/sophia")
local uv = require('uv')
local pathJoin = require('luvi').path.join


local function test(storage)
  local hash = assert(storage:save("blob 12\0Hello World\n"))
  p{hash=hash}
  local value = assert(storage:load(hash))
  p{value=value}
end

coroutine.wrap(function ()
  print("Initializing storage backend")
  test(GitStorage:new(pathJoin(uv.cwd(), "db.git")))
  test(SophiaStorage:new(pathJoin(uv.cwd(), "db.sophia")))
end)()
