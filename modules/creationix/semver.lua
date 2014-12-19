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
  local a, b, c = parse(version)
  return a .. '.' .. b .. '.' .. c
end
exports.normalize = normalize

function exports.max(first, second)
  if not first then return second end
  local a, b, c = parse(first)
  local d, e, f = parse(second)
  if (d > a) or (d == a and (e > b or (e == b and f > c))) then
    return d .. '.' .. e .. '.' .. f
  else
    return a .. '.' .. b .. '.' .. c
  end
end

-- Given a semver string in the format a.b.c, and a list of versions in the
-- same format, return the newest version that is compatable. This means for
-- 0.b.c versions, 0.b.(>= c) will match, and for a.b.c, versions a.(>=b).*
-- will match.
function match(version, iterator)
  --           Major Minor Patch
  -- found     a     b     c
  -- possible  d     e     f
  -- minimum   g     h     i
  local a, b, c
  if not version then
    -- With a n empty match, simply grab the newest version
    for possible in iterator do
      local d, e, f = parse(possible)
      if (not a) or (d > a) or (d == a and (e > b or (e == b and f > c))) then
        a, b, c = d, e, f
      end
    end
  else
    local g, h, i = parse(version)
    if g > 0 then
      -- From 1.0.0 and onward, minor updates are allowed since they mean non-
      -- breaking changes or additons.
      for possible in iterator do
        local d, e, f = parse(possible)
        if d == g and e >= h and ((not a) or e > b or (e == b and f > c)) then
          a, b, c = d, e, f
        end
      end
    else
      -- Before 1.0.0 we only allow patch updates assuming less stability at
      -- this period.
      for possible in iterator do
        local d, e, f = parse(possible)
        if d == g and e == h and f >= i and ((not a) or f > c) then
          a, b, c = d, e, f
        end
      end
    end
  end
  return a and (a .. '.' .. b .. '.' .. c)
end
exports.match = match
