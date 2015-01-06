local httpDecoder = require('creationix/http-codec').decoder
local jsonParse = require('creationix/json').parse
local env = require('env')
local exec = require('./exec')
local sshRsa = require('creationix/ssh-rsa')
local log = require('./log')

return function (storage, username)

  local url = "https://api.github.com/users/" .. username .. "/keys"
  local options = {"-i"}
  -- Set GITHUB_TOKEN to a token from https://github.com/settings/tokens/new to increase the rate limit
  local token = env.get("GITHUB_TOKEN")
  if token then
    options[#options + 1] = "-H"
    options[#options + 1] = "Authorization: token " .. token
  end
  local etag = storage.readKey(username, "etag")
  if etag then
    options[#options + 1] = "-H"
    options[#options + 1] = "If-None-Match: " .. etag
  end
  options[#options + 1] = url
  local head, json = httpDecoder()(assert(exec("curl", unpack(options))))
  if head.code == 304 then return url end
  if head.code == 404 then
    error("No such username at github: " .. username)
  end

  if head.code ~= 200 then
    p(head)
    error("Invalid http response from github API: " .. head.code)
  end

  for i = 1, #head do
    local name, value = unpack(head[i])
    if name:lower() == "etag" then etag = value end
  end
  local fingerprints = {}
  storage.writeKey(username, "etag", etag)
  local keys = jsonParse(json)
  for i = 1, #keys do
    local sshKey = sshRsa.loadPublic(keys[i].key)
    local fingerprint = sshRsa.fingerprint(sshKey)
    fingerprints[fingerprint] = sshKey
  end

  local iter = storage.fingerprints(username)
  if iter then
    for fingerprint in iter do
      if fingerprints[fingerprint] then
        fingerprints[fingerprint]= nil
      else
        log("revoking key", username .. ' ' .. fingerprint)
        storage.revokeKey(username, fingerprint)
      end
    end
  end

  for fingerprint, sshKey in pairs(fingerprints) do
    log("importing key", username .. ' ' .. fingerprint)
    assert(storage.writeKey(username, fingerprint, sshRsa.writePublic(sshKey)))
  end

  return url
end
