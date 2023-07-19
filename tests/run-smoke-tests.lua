-- Dependencies
local ffi = require("ffi")

-- Upvalues
local format = string.format

-- Allow running tests without passing the executable path to automatically test the installed version
local cliArguments = args -- Where does this even come from? Seems like more hidden luvit magic

local isWindows = (ffi.os == "Windows")
local DEFAULT_EXECUTABLE_NAME = isWindows and "lit.exe" or "lit"
local LIT_EXECUTABLE_PATH = cliArguments[2] or DEFAULT_EXECUTABLE_NAME

print(isWindows, DEFAULT_EXECUTABLE_NAME, LIT_EXECUTABLE_PATH)

local function RunSmokeTests()
	print("Running smoke tests (build verification)\n")

	-- All the CLI commands should probably be tested here (TODO: Actually implement these tests)
	-- Note: This is far too large a task to do all at once, so adding more tests here gradually is recommended
	local testCases = {
		[LIT_EXECUTABLE_PATH] = true -- Test if the path is set correctly
		-- This is the most basic test I can think of, poorly-structured and mostly intended to demonstrate a possible approach
		-- If the command has any side effects, like installing packages etc., they should be tested, too
	}

	for command, _ in pairs(testCases) do
		print(format("Testing command: %s\n", command))

		local success = os.execute(command)
		assert(success == true, "Failed to execute " .. command)

		print(format("All test passed for command: %s", command))
	end

	print("\nBuild Verification suceeded")
end

RunSmokeTests()
