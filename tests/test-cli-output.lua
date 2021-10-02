-- This can hardly be called a proper test, but it should help refactoring the CLI functionality (no logic should be changed)

local commands = {
	["luvi ."] = "lit.txt",
	["luvi . -- help"] = "lit-help.txt",
	["luvi . -- version"] = "lit-version.txt",
	["luvi . -- ls"] = "lit-ls.txt",
	["luvi . -- asdf"] = "invalid-command.txt",
	-- The others can't be tested in this fashion (and I guess it isn't necessary; if the CLI breaks all of the above should fail)
}

for command, fixturesFile in pairs(commands) do
	print("Testing command: " .. command)
	-- TBD: Does this work in the regular Win10 shell? (Probably doesn't matter if not, since these tests need to be reworked later, anyway)
	os.execute(command .. " | tee > lit-output.txt")

	-- I have no idea if/how to read from STDIN directly here, but this does seem like a bit of a hack...
	local temporaryFile = io.open("lit-output.txt", "r")
	local consoleOutput = temporaryFile:read("*all")
	temporaryFile:close()

	local expectedOutput = io.open("tests/fixtures/cli-output/" .. fixturesFile, "r"):read("*all")
	assert(consoleOutput == expectedOutput, "CLI output mismatch for command: lit" .. "\n\t" .. consoleOutput)

	-- Teardown
	os.execute("rm lit-output.txt")
end