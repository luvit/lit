require('luvi').bundle.register("luvit-require", "modules/require.lua");
local require = require('luvit-require')()("bundle:main.lua")
local luvit = require('luvit')
luvit.init()
coroutine.wrap(function ()
  local log = require('lit-log')
  log("lit version", "0.0.1")
  args[1] = args[1] or "help"
  log("command", table.concat(args, " "))
  require("./commands/" .. args[1] .. ".lua")
  log("done", "success", "success")
end)()
luvit.run()
