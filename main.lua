local luvi = require('luvi')
local bundle = luvi.bundle

-- Manually register the require replacement system to bootstrap things
bundle.register("luvit-require", "modules/require.lua");
-- Upgrade require system in-place
local require = require('luvit-require')()("bundle:modules/main.lua")

local luvit = require('luvit')
luvit.init()

local sophia = require('sophia.so')

p(sophia)

luvit.run()

return _G.process.exitCode
