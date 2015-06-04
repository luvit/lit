local fs = require('coro-fs')
local uv = require('uv')
local getInstalled = require('get-installed')

local deps = getInstalled(fs, uv.cwd())

local aliases = {}
for alias in pairs(deps) do
  aliases[#aliases + 1] = alias
end
table.sort(aliases)

local max = 0
for i = 1, #aliases do
  local alias = aliases[i]
  local meta = deps[alias]
  if #meta.name > max then
    max = #meta.name
  end
end

for i = 1, #aliases do
  local alias = aliases[i]
  local meta = deps[alias]
  local base = meta.name:match("([^/]+)$")
  local line = string.format("%-" .. max .. "s v%s", meta.name, meta.version)
  if not meta.location:match("deps$") then
    line = line .. " (local)"
  end
  if base ~= alias then
    line = line .. " (as " .. alias .. ")"
  end
  print(line)
end
