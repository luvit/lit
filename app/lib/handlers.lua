local log = require('../lib/log')
local config = require('../lib/config')
local db = config.db
local storage = db.storage
local git = require('creationix/git')
local digest = require('openssl').digest.digest
local importKeys = require('../lib/import-keys')
local sshRsa = require('creationix/ssh-rsa')

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
    if not sshRsa.verify(body, signature, sshKey) then
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
