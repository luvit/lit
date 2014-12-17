exports.name = "creationix/semver"
exports.version = "1.0.0"
-- Make the module itself callable
setmetatable(exports, {
  __call = function (_, ...)
    return exports.match(...)
  end
})

local function parse(version)
  local major, minor, patch = string.match(version, "(%d+)%.(%d+)%.(%d+)")
  return tonumber(major), tonumber(minor), tonumber(patch)
end

-- Given a semver string in the format a.b.c, and a list of versions in the
-- same format, return the newest version that is compatable. This means for
-- 0.b.c versions, 0.b.(>= c) will match, and for a.b.c, versions a.(>=b).*
-- will match.
function exports.match(version, versions)
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
