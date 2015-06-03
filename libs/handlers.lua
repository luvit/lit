local log = require('log')
local git = require('git')
local digest = require('openssl').digest.digest
local sshRsa = require('ssh-rsa')
local githubQuery = require('./github-request')
local jsonParse = require('json').parse

local function split(line)
  local args = {}
  for match in string.gmatch(line, "[^ ]+") do
    args[#args + 1] = match
  end
  return unpack(args)
end

return function (core)
  local db = core.db
  local handlers = {}

  function handlers.read(remote, data)
    local name, version = split(data)
    local author
    author, name = name:match("([^/]+)/(.*)")
    -- TODO: check for mismatch
    local hash = db.read(author, name, version)
    remote.writeAs("reply", hash)
  end

  function handlers.match(remote, data)
    local name, version = split(data)
    local author
    author, name = name:match("([^/]+)/(.*)")
    if not name then
      return remote.writeAs("error", "Missing name parameter")
    end
    local match, hash = db.match(author, name, version)
    if not match and hash then
      error(hash)
    end
    remote.writeAs("reply", match and (match .. ' ' .. hash))
  end

  function handlers.wants(remote, hashes)
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

  function handlers.want(remote, hash)
    return handlers.wants(remote, {hash})
  end

  local function verifySignature(username, raw)
    core.importKeys(username)
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
    local sshKey = db.readKey(username, fingerprint)
    if not sshKey then
      local iter = db.owners(username)
      if iter then
        for owner in iter do
          core.importKeys(owner)
          sshKey = db.readKey(owner, fingerprint)
          if sshKey then break end
        end
        if not sshKey then
          error("Not in group: " .. username)
        end
      end
      if not sshKey then
        error("Invalid fingerprint")
      end
    end
    sshKey = sshRsa.loadPublic(sshKey)
    assert(sshRsa.fingerprint(sshKey) == fingerprint, "fingerprint mismatch")
    return sshRsa.verify(body, signature, sshKey)
  end

  function handlers.send(remote, data)
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
      if not db.has(hash) then
        wants[#wants + 1] = hash
        authorized[hash] = true
      end
    end

    if #wants > 0 then
      remote.writeAs("wants", wants)
    elseif not next(authorized) then
      local tag = remote.tag
      local author, name, version = string.match(tag.tag, "([^/]+)/(.*)/v(.*)")
      db.write(author, name, version, tag.hash)
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

  function handlers.claim(remote, raw)
    -- The request is RSA signed by the .username field.
    -- This will verify the signature and return the data table
    local data = verifyRequest(raw)
    local username, org = data.username, data.org

    if db.isOwner(org, username) then
      error("Already an owner in org: " .. org)
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
      error("Not a public member of org: " .. org)
    end

    db.addOwner(org, username)
    remote.writeAs("reply", "claimed")
  end

  function handlers.share(remote, raw)
    local data = verifyRequest(raw)
    local username, org, friend = data.username, data.org, data.friend
    if not db.isOwner(org, username) then
      error("Can't share a org you're not in: " .. org)
    end
    if (db.isOwner(org, friend)) then
      error("Friend already in org: " .. friend)
    end
    db.addOwner(org, friend)

    remote.writeAs("reply", "shared")
  end

  function handlers.unclaim(remote, raw)
    local data = verifyRequest(raw)
    local username, org = data.username, data.org

    if not db.isOwner(org, username) then
      error("Non a member of org: " .. org)
    end
    db.removeOwner(org, username)


    remote.writeAs("reply", "unshared")
  end

  return handlers
end
