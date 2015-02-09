local log = require('../lib/log')
local config = require('../lib/config')
local db = config.db
local storage = db.storage
local git = require('git')
local digest = require('openssl').digest.digest
local importKeys = require('../lib/import-keys')
local sshRsa = require('ssh-rsa')
local githubQuery = require('./github-request')
local jsonParse = require('json').parse
local jsonStringify = require('json').stringify

local function split(line)
  local args = {}
  for match in string.gmatch(line, "[^ ]+") do
    args[#args + 1] = match
  end
  return unpack(args)
end

function exports.read(remote, data)
  local name, version = split(data)
  -- TODO: check for mismatch
  local hash = db.read(name, version)
  remote.writeAs("reply", hash)
end

function exports.match(remote, data)
  local name, version = split(data)
  if not name then
    return remote.writeAs("error", "Missing name parameter")
  end
  local match, hash = db.match(name, version)
  if not match and hash then
    error(hash)
  end
  remote.writeAs("reply", match and (match .. ' ' .. hash))
end

function exports.wants(remote, hashes)
  for i = 1, #hashes do
    local hash = hashes[i]
    local data, err = db.load(hash)
    if not data then
      return remote.writeAs("error", err or "No such hash: " .. hash)
    end
    local kind, raw = git.deframe(data)
    if kind == 'tag' then
      local tag = git.decoders.tag(raw)
      log("client want", tag.tag)
    else
      log("client want", hash, "string")
    end
    remote.writeAs("send", data)
  end
end

function exports.want(remote, hash)
  return exports.wants(remote, {hash})
end

local function verifySignature(username, raw)
  importKeys(storage, username)
  local body, fingerprint, signature = string.match(raw, "^(.*)"
    .. "%-%-%-%-%-BEGIN RSA SIGNATURE%-%-%-%-%-\n"
    .. "Format: sha256%-ssh%-rsa\n"
    .. "Fingerprint: ([^\n]+)\n\n"
    .. "(.*)\n"
    .. "%-%-%-%-%-END RSA SIGNATURE%-%-%-%-%-")

  if not signature then
    error("Missing sha256-ssh-rsa signature")
  end
  signature = signature:gsub("\n", "")
  local sshKey = storage.readKey(username, fingerprint)
  if not sshKey then
    error("Invalid fingerprint")
  end
  sshKey = sshRsa.loadPublic(sshKey)
  assert(sshRsa.fingerprint(sshKey) == fingerprint, "fingerprint mismatch")
  return sshRsa.verify(body, signature, sshKey)
end

function exports.send(remote, data)
  local authorized = remote.authorized or {}
  local kind, raw = git.deframe(data)
  local hashes = {}

  local hash = digest("sha1", data)
  if kind == "tag" then
    if remote.tag then
      return remote.writeAs("error", "package upload already in progress: " .. remote.tag.tag)
    end
    local tag = git.decoders.tag(raw)
    local username = string.match(tag.tag, "^[^/]+")
    if not verifySignature(username, raw) then
      return remote.writeAs("error", "Signature verification failure")
    end
    tag.hash = hash
    remote.tag = tag
    remote.authorized = authorized
    hashes[#hashes + 1] = tag.object
  else
    if not authorized[hash] then
      return remote.writeAs('error', "Attempt to send unauthorized object: " .. hash)
    end
    authorized[hash] = nil
    if kind == "tree" then
      local tree = git.decoders.tree(raw)
      for i = 1, #tree do
        hashes[#hashes + 1] = tree[i].hash
      end
    end
  end
  assert(db.save(data) == hash)

  local wants = {}
  for i = 1, #hashes do
    local hash = hashes[i]
    if not storage.has(hash) then
      wants[#wants + 1] = hash
      authorized[hash] = true
    end
  end

  if #wants > 0 then
    remote.writeAs("wants", wants)
  elseif not next(authorized) then
    local tag = remote.tag
    local name, version = string.match(tag.tag, "(.*)/v(.*)")
    storage.writeTag(name, version, tag.hash)
    log("new package", tag.tag)
    remote.writeAs("done", tag.hash)
    remote.tag = nil
    remote.authorized = nil
  end

end

local function verifyRequest(raw)
  local data = assert(jsonParse(string.match(raw, "([^\n]+)")))
  assert(verifySignature(data.username, raw), "Signature verification failure")
  return data
end

function exports.claim(remote, raw)
  -- The request is RSA signed by the .username field.
  -- This will verify the signature and return the data table
  local data = verifyRequest(raw)
  local username, org = data.username, data.org

  if storage.readKey(org, "owners") then
    error("Org already claimed: " .. org)
  end

  local head, members = githubQuery("/orgs/" .. org .. "/public_members")
  if head.code == 404 then
    error("Not an org name: " .. org)
  end
  local member = false
  for i = 1, #members do
    if members[i].login == username then
      member = true
      break
    end
  end
  if not member then
    error("Not a public member of: " .. org)
  end

  assert(storage.writeKey(org, "owners", username))
  remote.writeAs("reply", "claimed")
end

function exports.share(remote, raw)
  local data = verifyRequest(raw)
  local username, org, friend = data.username, data.org, data.friend
  local owners = storage.readKey(org, "owners")
  if not owners then
    error("No such claimed group: " .. org)
  end
  local found = false
  for owner in owners:gmatch("[^\n]+") do
    if owner == username then
      found = true
    end
    if owner == friend then
      error("Friend already in group: " .. friend)
    end
  end
  if not found then
    error("Can't share a group you're not in: " .. org)
  end

  assert(storage.writeKey(org, "owners", owners .. "\n" .. friend))

  remote.writeAs("reply", "shared")
end

function exports.unclaim(remote, raw)
  local data = verifyRequest(raw)
  local username, org = data.username, data.org

  local found
  local owners = {}
  for owner in storage.readKey(org, "owners"):gmatch("[^\n]+") do
    if owner == username then
      found = true
    else
      owners[#owners + 1] = owner
    end
  end
  if not found then
    error("Non a member of group: " .. org)
  end

  if #owners > 0 then
    assert(storage.writeKey(org, "owners", table.concat(owners, "\n")))
  else
    assert(storage.revokeKey(org, "owners"))
  end

  remote.writeAs("reply", "unshared")
end
