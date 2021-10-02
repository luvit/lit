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

local bundle = require("luvi").bundle
loadstring(bundle.readfile("luvit-loader.lua"), "bundle:luvit-loader.lua")()

-- Upvalues
local uv = require("uv")
local version = require("./package").version
local log = require("log").log
require("snapshot")

-- Global setup
_G.p = require("pretty-print").prettyPrint

-- Settings
local EXIT_SUCCESS = 0
local EXIT_FAILURE = -1

local aliases = {
	["-v"] = "version",
	["-h"] = "help"
}

local Lit = {}

local CLI = {}

function CLI:Run()
	coroutine.wrap(
		function()
			self:ProcessUserInput()
		end
	)()
	uv.run()
end

function CLI:ProcessUserInput()
	local command = self:ProcessArguments()
	local success, errorMessage =
		xpcall(
		function()
			self:ExecuteCommand(command)
		end,
		debug.traceback
	)

	if not success then
		self:ReportFailure(errorMessage)
		return
	end

	self:ReportSuccess()
end

function CLI:ProcessArguments()
	local command = args[1] or "help"
	if command:sub(1, 2) == "--" then
		command = command:sub(3)
	end
	command = aliases[command] or command
	return command
end

function CLI:ExecuteCommand(command)
	self:OutputVersionInfo()

	if command == "version" then
		-- Since the version is always printed, there's nothing left to do
		self:ExitWithCode(EXIT_SUCCESS)
	end

	if self:IsValidCommand(command) then
		log("command", table.concat(args, " "), "highlight")
		self:ExecuteCommandHandler(command)
	else
		log("invalid command", command, "failure")
		self:ExecuteCommandHandler("help")
		self:ReportFailure("Invalid Command: " .. command)
	end
end

function CLI:ReportSuccess()
	log("done", "success", "success")
	print()
	self:ExitWithCode(EXIT_SUCCESS)
end

function CLI:ReportFailure(errorMessage)
	log("fail", errorMessage, "failure")
	print()
	self:ExitWithCode(EXIT_FAILURE)
end

function CLI:OutputVersionInfo()
	log("lit version", version)
	log("luvi version", require("luvi").version)
end

function CLI:ExitWithCode(exitCode)
	uv.walk(
		function(handle)
			if handle then
				local function close()
					if not handle:is_closing() then
						handle:close()
					end
				end
				if handle.shutdown then
					handle:shutdown(close)
				else
					close()
				end
			end
		end
	)
	uv.run()
	os.exit(exitCode)
end

function CLI:IsValidCommand(command)
	local commandHandler = "./commands/" .. command .. ".lua"
	return bundle.stat(commandHandler:sub(3)) -- A command is valid if a script handler for it exists
end

function CLI:ExecuteCommandHandler(command)
	local commandHandler = "./commands/" .. command .. ".lua"
	require(commandHandler)()
end

Lit.CLI = CLI

CLI:Run()
