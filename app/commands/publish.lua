local config = require('../lib/config')
local uv = require('uv')
local pathJoin = require('luvi').path.join
local db = config.db

local cwd = uv.cwd()
if #args > 1 then
  for i = 2, #args do
    db.publish(config, pathJoin(cwd, args[i]))
  end
else
  db.publish(config, cwd)
end
