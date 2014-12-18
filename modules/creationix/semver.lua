exports.name = "creationix/semver"
exports.version = "1.0.0"
local parse, normalize, match
-- Make the module itself callable
setmetatable(exports, {
  __call = function (_, ...)
    return match(...)
  end
})

function parse(version)
  if not version then return end
  return
    assert(tonumber(string.match(version, "^v?(%d+)")), "Not a semver"),
    tonumber(string.match(version, "^v?%d+%.(%d+)") or 0),
    tonumber(string.match(version, "^v?%d+%.%d+%.(%d+)") or 0)
end
exports.parse = parse

function normalize(version)
  if not version then return "*" end
  return table.concat({parse(version)}, ".")
end
exports.normalize = normalize


-- Given a semver string in the format a.b.c, and a list of versions in the
-- same format, return the newest version that is compatable. This means for
-- 0.b.c versions, 0.b.(>= c) will match, and for a.b.c, versions a.(>=b).*
-- will match.
function match(version, versions)
  if #versions == 0 then return end
  local found
  if not version or version == "*" then
    -- With a * match, simply grab the newest version
    for i = 1, #versions do
      local match = {parse(versions[i])}
      if not found or match[1] > found[1] then
        found = match
      end
    end
  else
    local wanted = {parse(version)}
    if not wanted[1] then return end
    if wanted[1] > 0 then
      -- From 1.0.0 and onward, minor updates are allowed since they mean non-
      -- breaking changes or additons.
      for i = 1, #versions do
        local match = {parse(versions[i])}
        if match[1] == wanted[1] and (
          found and match[2] > found[2]
                or match[2] >= wanted[2]) then
          found = match
        end
      end
    else
      -- Before 1.0.0 we only allow patch updates assuming less stability at
      -- this period.
      for i = 1, #versions do
        local match = {parse(versions[i])}
        if match[2] == wanted[2] and (
          found and match[3] > found[3]
                or match[3] >= wanted[3]) then
          found = match
        end
      end
    end
  end
  return found and table.concat(found, '.')
end
exports.match = match
