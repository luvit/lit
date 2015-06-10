local core = require('core')()
local uv = require('uv')
local pathJoin = require('luvi').path.join

local cwd = uv.cwd()
local source = args[2] and pathJoin(cwd, args[2])
local target = args[3] and pathJoin(cwd, args[3])
if not source or uv.fs_access(source, "r") then
  core.make(source or cwd, target)
else
  core.makeUrl(args[2], target)
end
