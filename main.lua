local uv = require('uv')
require('luvi').bundle.register("luvit-require", "deps/require.lua")
local require = require('luvit-require')("bundle:main.lua")

_G.p = require('pretty-print').prettyPrint
local version = require('./package').version
coroutine.wrap(function ()
  local log = require('log')
  local success, err = xpcall(function ()
    log("lit version", version)
    args[1] = args[1] or "help"
    if args[1] == "version" then os.exit(0) end
    log("command", table.concat(args, " "), "highlight")
    require("./commands/" .. args[1] .. ".lua")
  end, debug.traceback)
  if success then
    log("done", "success", "success")
    print()
    os.exit(0)
  else
    log("fail", err, "failure")
    print()
    os.exit(-1)
  end
end)()
uv.run()
