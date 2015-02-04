local env = require('env')
local httpCodec = require('creationix/http-codec')
local jsonParse = require('creationix/json').parse
local sshRsa = require('creationix/ssh-rsa')
local connect = require('creationix/coro-tcp').connect
local tlsWrap = require('creationix/coro-tls').wrap
local wrapper = require('./wrapper')
local log = require('./log')

return function (storage, username)

  local path = "/users/" .. username .. "/keys"
  local url = "https://api.github.com" .. path

  local req = {
    method = "GET",
    path = path,
    {"Host", "api.github.com"},
    {"User-Agent", "lit"},
  }

  -- Set GITHUB_TOKEN to a token from https://github.com/settings/tokens/new to increase the rate limit
  local token = env.get("GITHUB_TOKEN")
  if token then
    req[#req + 1] = {"Authorization", "token " .. token}
  end

  local etag = storage.readKey(username, "etag")
  if etag then
    req[#req + 1] = {"If-None-Match", etag}
  end

  local read, write = assert(connect("api.github.com", "https"))
  read, write = tlsWrap(read, write)

  read = wrapper.reader(read, httpCodec.decoder())
  write = wrapper.writer(write, httpCodec.encoder())

  write(req)
  local head = read()
  local json = {}
  for item in read do
    if #item == 0 then break end
    json[#json + 1] = item
  end
  write()
  json = table.concat(json)
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

  return url
end
