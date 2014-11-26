local uv = require('uv')
local db = require('./git-fs')("test.git")
local pathJoin = require('luvi').path.join

coroutine.wrap(function ()
  db:init()
  local path = pathJoin(uv.cwd(), "sample-lib")
  local hash = db:import(path)
  print("Imported " .. path .. " as " .. hash)
end)()

