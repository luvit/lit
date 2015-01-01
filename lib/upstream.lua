local digest = require('openssl').digest.digest
local git = require('creationix/git')
local deframe = git.deframe
local decodeTag = git.decoders.tag
local decodeTree = git.decoders.tree
local connect = require('creationix/coro-tcp').connect
local makeRemote = require('./codec').makeRemote

return function (storage, host, port)
local read, write, socket = assert(connect(host, port or 4821))
  local remote = makeRemote(read, write)
  local upstream = {}

  -- Client: SEND tagObject

  -- Server: WANTS objectHash

  -- Client: SEND object

  -- Server: WANTS ...

  -- Client: SEND ...
  -- Client: SEND ...
  -- Client: SEND ...

  -- Server: DONE hash
  function upstream.push(hash)
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

  function upstream.pull(hash)
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
          refs[tag.tag] = hash
          -- Check if we have the object the tag points to.
          if not storage.has(tag.object) then
            -- If not, add it to the list
            table.insert(list, tag.object)
          end
        elseif kind == "tree" then
          local tree = decodeTree(body)
          for i = 1, #tree do
            local subHash = tree[i].hash
            if not storage.has(subHash) then
              table.insert(list, subHash)
            end
          end
        end
        storage.save(data)
      end
    until #list == 0
    for ref, hash in pairs(refs) do
      storage.write(ref, hash)
    end
    return refs
  end

      -- Client: WANTS hash

      -- Server: SEND data

  function upstream.load(hash)
    remote.writeAs("wants", {hash})
    local data = remote.readAs("send")
    assert(digest("sha1", data) == hash, "hash mismatch in result object")
    storage.save(data)
    return data
  end

      -- Client: MATCH name version

      -- SERVER: REPLY version hash

  function upstream.read(name, version)
    remote.writeAs("read", name .. " " .. version)
    local data = assert(remote.readAs("reply"))
    local match, hash = string.match(data, "^([^ ]+) (.*)$")
    return match, hash
  end

  function upstream.match(name, version)
    remote.writeAs("match", version and (name .. " " .. version) or name)
    local data = assert(remote.readAs("reply"))
    local match, hash = string.match(data, "^([^ ]+) (.*)$")
    return match, hash
  end

  --[[
  upstream.close()
  ----------------

  Called when the db is done with the connection.
  ]]--
  function upstream.close()
    return socket:close()
  end

  return upstream

end

