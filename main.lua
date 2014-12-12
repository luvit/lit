require('luvi').bundle.register("luvit-require", "modules/require.lua");
local require = require('luvit-require')()("bundle:main.lua")
local luvit = require('luvit')
luvit.init()
require("./commands/" .. (args[1] or "repl") .. ".lua")
luvit.run()
