local digest = require('openssl').digest.digest
local git = require('creationix/git')
local deframe = git.defame
local decodeTag = git.decoders.tag
local decodeTree = git.decoders.tree

    -- Client: SEND tagObject

    -- Server: WANTS objectHash

    -- Client: SEND object

    -- Server: WANTS ...

    -- Client: SEND ...
    -- Client: SEND ...
    -- Client: SEND ...

    -- Server: DONE hash


local function push(storage, remote, hash)
  remote.writeAs("send", storage.load(hash))
  while true do
    local name, data = remote.read()
    if name == "wants" then
      for i = 1, #data do
        remote.writeAs("send", storage.load(data[i]))
      end
    elseif name == "done" then
      return data
    else
      error("Expected more wants or done in reply to send to server")
    end
  end
end

      -- Client: WANT tagHash

      -- Server: SEND tagObject

      -- Client: WANT objectHash

      -- Server: SEND object

      -- Client: WANT ...
      -- Client: WANT ...
      -- Client: WANT ...

      -- Server: SEND ...
      -- Server: SEND ...
      -- Server: SEND ...

local function pull(storage, remote, hash)
  local list = {hash}
  local refs = {}
  repeat
    local hashes = list
    list = {}
    remote.writeAs("wants", hashes)
    for i = 1, #hashes do
      local hash = hashes[i]
      local data = remote.readAs("send")
      assert(digest("sha1", data) == hash, "hash mismatch in result object")
      local kind, body = deframe(data)
      if kind == "tag" then
        local tag = decodeTag(body)
        -- TODO: verify tag
        refs[tag.ref] = hash
        -- Check if we have the object the tag points to.
        if not storage.have(tag.object) then
          -- If not, add it to the list
          table.insert(list, tag.object)
        end
      elseif kind == "tree" then
        local tree = decodeTree(body)
        for i = 1, #tree do
          local subHash = tree[i].hash
          if not storage.have(subHash) then
            table.insert(list, subHash)
          end
        end
      end
      storage.save(data)
    end
  until #list > 0
  for ref, hash in pairs(refs) do
    storage.write(ref, hash)
  end
  return refs
end

    -- Client: MATCH name version

    -- SERVER: REPLY version hash

local function match(remote, name, version)
  remote.writeAs("match", {name, version})
  return unpack(remote.readAs("reply"))
end
