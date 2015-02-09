local sshRsa = require('ssh-rsa')
local log = require('./log')
local githubQuery = require('./github-request')

return function (storage, username)

  local path = "/users/" .. username .. "/keys"
  local etag = storage.readKey(username, "etag")
  local head, keys, url = githubQuery(path, etag)

  if head.code == 304 then return url end
  if head.code == 404 then
    error("No such username at github: " .. username)
  end

  if head.code ~= 200 then
    p(head)
    error("Invalid http response from github API: " .. head.code)
  end

  local fingerprints = {}
  for i = 1, #keys do
    local sshKey = sshRsa.loadPublic(keys[i].key)
    if sshKey then
      local fingerprint = sshRsa.fingerprint(sshKey)
      fingerprints[fingerprint] = sshKey
    end
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

  for i = 1, #head do
    local name, value = unpack(head[i])
    if name:lower() == "etag" then etag = value end
  end
  assert(storage.writeKey(username, "etag", etag))

  return url
end
