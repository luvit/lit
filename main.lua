require('luvi').bundle.register("luvit-require", "modules/require.lua");
local require = require('luvit-require')()("bundle:main.lua")
local luvit = require('luvit')
luvit.init()
coroutine.wrap(function ()
  local log = require('./lib/log')
  local success, err = xpcall(function ()
    log("lit version", "0.0.1")
    args[1] = args[1] or "help"
    log("command", table.concat(args, " "))
    require("./commands/" .. args[1] .. ".lua")
  end, debug.traceback)
  if success then
    log("done", "success", "success")
    os.exit(0)
  else
    log("fail", err, "failure")
    os.exit(-1)
  end
end)()
luvit.run()
