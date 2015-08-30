local core = require("core")()
local prompt = require("prompt")(require("pretty-print"))
local fs = require("coro-fs")
local env = require("env")
local log = require("log").log
local pathJoin = require("luvi").path.join
local cwd = require('uv').cwd()

local config = core.config
local dirty = false

local function getOutput()
  local output = prompt("Output to package.lua (1), or a init.lua (2)?")
  -- response was blank, run again
  if not output then
    return getOutput()
  end
  -- fail on any other options
  if not output:match('[1-2]') then
    log("Error", "You must select a valid option. [1 or 2]")
    return getOutput()
  else
    if output == "1" then
      output = "package.lua"
      log("Creating", "package.lua")
    elseif output == "2" then
      output = "init.lua"
      log("Creating", "init.lua")
    end
  end
  return output
end

local output = getOutput()

local home = env.get("HOME") or env.get("HOMEPATH") or ""
local ini
local function getConfig(name)
  ini = ini or fs.readFile(pathJoin(home, ".gitconfig"))
  if not ini then return end
  local section
  for line in ini:gmatch("[^\n]+") do
    local s = line:match("^%[([^%]]+)%]$")
    if s then
      section = s
    else
      local key, value = line:match("^%s*(%w+)%s*=%s*(.+)$")
      if key and section .. "." .. key == name then
        if tonumber(value) then return tonumber(value) end
        if value == "true" then return true end
        if value == "false" then return false end
        return value
      end
    end
  end
end

local projectName = prompt("Project Name", config["username"] .. "/project-name")
local projectVersion = prompt("Version", "0.0.1")
local projectDescription = prompt("Description", "A simple description of my little package.")
local projectTags = prompt("Tags (Comma Separated)", "lua, lit, luvit")
local authorName = prompt("Author Name", getConfig("user.name"))
local authorEmail = prompt("Author Email", getConfig("user.email"))
local projectLicense = prompt("License", "MIT")
local projectHomepage = prompt("Homepage", "https://github.com/" .. projectName)

-- trim and wrap words in quotes
function makeTags(csv)
  local tags = "{ "
  for word in csv:gmatch('([^,]+)') do
    tags = tags .. "\"" .. word:gsub("^%s*(.-)%s*$", "%1") .. "\", "
  end
  -- trim trailing comma and space
  tags = tags:sub(0, (#tags - 2))
  return tags .. " }"
end

local data = ""

-- manually craft strings to control formatting
if output == "init.lua" then
  data = "exports.name = \"" .. projectName .. "\"\nexports.version = \"" .. projectVersion .. "\"\nexports.dependencies = {}\nexports.description = \"" .. projectDescription .. "\"\nexports.tags = " .. makeTags(projectTags) .. "\nexports.license = \"" .. projectLicense .. "\"\nexports.author = {\n  name = \"" .. authorName .. "\",\n  email = \"" .. authorEmail .. "\"\n}\nexports.homepage = \"" .. projectHomepage .. "\"\n"
elseif output == "package.lua" then
  data = "return {\n  name = \"" .. projectName .. "\",\n  version = \"" .. projectVersion .. "\",\n  description = \"" .. projectDescription .. "\",\n  tags = " .. makeTags(projectTags) .. ",\n  license = \"" .. projectLicense .. "\",\n  author = { name = \"" .. authorName .. "\", email = \"" .. authorEmail .. "\" },\n  homepage = \"" .. projectHomepage .. "\",\n  dependencies = {},\n  files = {\n    \"**.lua\",\n    \"!test*\"\n  }\n}\n"
end

print("\n" .. data .. "\n")

local message = "Enter to continue"
local finish = prompt("Is this ok?", message)

if finish == message then
  local data, err = fs.writeFile(cwd .. "/" .. output, data)
  if err == nil then
    log("Complete", "Created a new " .. output .. " file.")
  else
    log("Error", "Could not write file.")
  end
else
  log("Aborted", "No files will be written")
end
