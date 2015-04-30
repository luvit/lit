exports.name = "creationix/semver"
exports.version = "1.0.2"
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
    tonumber(string.match(version, "^v?%d+%.%d+%.(%d+)") or 0),
    tonumber(string.match(version, "^v?%d+%.%d+%.%d+-(%d+)") or 0)
end
exports.parse = parse

function normalize(version)
  if not version then return "*" end
  local a, b, c, d = parse(version)
  return a .. '.' .. b .. '.' .. c .. (d and ('-' .. d) or (''))
end
exports.normalize = normalize

-- Return true is first is greater than ot equal to the second
-- nil counts as lowest value in this case
function exports.gte(first, second)
  if not second or first == second then return true end
  if not first then return false end
  local a, b, c, x = parse(second)
  local d, e, f, y = parse(first)
  return (d > a) or (d == a and (e > b or (e == b and (f > c or (f == c and y > x)))))
end

-- Sanity check for gte code
assert(exports.gte(nil, nil))
assert(exports.gte("0.0.0", nil))
assert(exports.gte("9.9.9", "9.9.9"))
assert(exports.gte("9.9.10", "9.9.9"))
assert(exports.gte("9.10.0", "9.9.99"))
assert(exports.gte("10.0.0", "9.99.99"))
assert(exports.gte("10.0.0-1", "10.0.0-0"))
assert(exports.gte("10.0.1-0", "10.0.0-0"))
assert(exports.gte("10.0.1", "10.0.0-10"))
assert(not exports.gte(nil, "0.0.0"))
assert(not exports.gte("9.9.9", "9.9.10"))
assert(not exports.gte("9.9.99", "9.10.0"))
assert(not exports.gte("9.99.99", "10.0.0"))
assert(not exports.gte("10.0.0-0", "10.0.0-1"))

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
        if d == g and ((e == h and f >= i) or e > h) and ((not a) or e > b or (e == b and f > c)) then
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

local function iterator()
  local versions = {"0.0.1", "0.0.2", "0.1.0", "0.1.1", "0.2.0", "0.2.1", "1.0.0", "1.1.0", "1.1.3", "2.0.0", "2.1.2", "3.1.4"}
  local i = 0
  return function ()
    i = i + 1
    return versions[i]
  end
end

-- Sanity check for match code
assert(match("0.0.1", iterator()) == "0.0.2")
assert(match("0.0.1-1", iterator()) == "0.0.2")
assert(match("0.1.0", iterator()) == "0.1.1")
assert(match("0.1.0-1", iterator()) == "0.1.1")
assert(match("0.2.0", iterator()) == "0.2.1")
assert(not match("0.3.0", iterator()))
assert(match("1.0.0", iterator()) == "1.1.3")
assert(match("1.0.0-1", iterator()) == "1.1.3")
assert(not match("1.1.4", iterator()))
assert(not match("1.2.0", iterator()))
assert(match("2.0.0", iterator()) == "2.1.2")
assert(not match("2.1.3", iterator()))
assert(not match("2.2.0", iterator()))
assert(match("3.0.0", iterator()) == "3.1.4")
assert(not match("3.1.5", iterator()))
assert(match(nil, iterator()) == "3.1.4")
