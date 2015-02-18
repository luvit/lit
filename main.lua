require('luvi').bundle.register("luvit-require", "modules/require.lua");
local uv = require('uv')
local require = require('luvit-require')()("bundle:main.lua")
_G.p = require('pretty-print').prettyPrint
local version = require('./package').version
coroutine.wrap(function ()
  local log = require('./lib/log')
  local success, err = xpcall(function ()
    log("lit version", version)
    args[1] = args[1] or "help"
    log("command", table.concat(args, " "), "highlight")
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
uv.run()
