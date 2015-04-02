local request = require('coro-http').request
local semver = require('semver')
local jsonParse = require('json').parse

-- Feed auto-updater your package.lua pre-parsed as a lua table
function exports.check(meta)
  local name = meta.name
  local version = meta.version
  assert(version and name, "Missing name or version in own metadata")
  version = semver.normalize(version)
  local head, body = request("GET", "http://lit.luvit.io/packages/" .. meta.name)
  assert(head.code == 200)
  local versions = assert(jsonParse(body), "Problem parsing JSON response from lit")
  local key
  return semver.match(version, function ()
    local n = next(versions, key)
    key = n
    return key
  end)
end

