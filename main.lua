--[[

Copyright 2014-2015 The Luvit Authors. All Rights Reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS-IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

--]]

local uv = require('uv')
require('luvi').bundle.register("luvit-require", "deps/require.lua")
local bundle = require('luvi').bundle
local require = require('luvit-require')("bundle:main.lua")

local aliases = {
  ["-v"] = "version",
  ["-h"] = "help",
}

_G.p = require('pretty-print').prettyPrint
local version = require('./package').version
coroutine.wrap(function ()
  local log = require('log').log
  local command = args[1] or "help"
  if command:sub(1, 2) == "--" then
    command = command:sub(3)
  end
  command = aliases[command] or command
  local invalid = false
  local success, err = xpcall(function ()
    log("lit version", version)
    log("luvi version", require('luvi').version)
    if command == "version" then os.exit(0) end
    local path = "./commands/" .. command .. ".lua"
    if bundle.stat(path:sub(3)) then
      log("command", table.concat(args, " "), "highlight")
    else
      invalid = command
      log("invalid command", command, "failure")
      command = "help"
      path = "./commands/" .. command .. ".lua"
    end
    require(path)
  end, debug.traceback)
  if invalid then
    success = false
    err = "Invalid Command: " .. invalid
  end
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
