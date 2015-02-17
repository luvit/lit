local fs = require('coro-fs')
local env = require('env')

local prefix
if require('ffi').os == "Windows" then
  prefix = env.get("APPDATA") .. "\\"
else
  prefix = env.get("HOME") .. "/."
end

local configFile = env.get("LIT_CONFIG") or (prefix .. "litconfig")

local config = {}
local data = fs.readFile(configFile)
if data then
  for key, value in string.gmatch(data, "([^:\n]+): *([^\n]+)") do
    config[key] = value
  end
end

local storage = require('../lib/storage')(config.database)
p(storage)
p(storage.read("refs/tags/creationix/coro-fs/v1.2.0"))

for author in storage.nodes("refs/tags") do
  local prefix = "refs/tags/" .. author
  for tag in storage.nodes(prefix) do
    local path = prefix .. "/" .. tag
    for version in storage.leaves(path) do
      p(author .. '/' .. tag .. '@' .. version)
    end
  end
end
storage.write("test", "stuff")
p(storage.read("bad"), storage.read("test"))
p("missing")
for name in storage.nodes("no such") do
  p("WHAT!", name)
end
storage.put("test2", "first")
storage.put("test2", "second")
p(storage.read("test2"))
storage.delete("test")
storage.delete("test2")
storage.put("a/b/c/d", "hello")
storage.delete("a/b/c/d", "hello")
