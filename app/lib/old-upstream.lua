local openssl = require('openssl')
local digest = openssl.digest.digest
local connect = require('coro-tcp').connect
local httpCodec = require('http-codec')
local websocketCodec = require('websocket-codec')

local git = require('git')
local deframe = git.deframe
local decodeTag = git.decoders.tag
local decodeTree = git.decoders.tree

local makeRemote = require('./codec').makeRemote
local wrapper = require('./wrapper')
local tlsWrap = require('coro-tls').wrap
local readWrap, writeWrap = wrapper.reader, wrapper.writer

return function (db, url)
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



      -- Client: WANTS hash

      -- Server: SEND data

  function upstream.load(hash)
    remote.writeAs("wants", {hash})
    local data = remote.readAs("send")
    assert(digest("sha1", data) == hash, "hash mismatch in result object")
    return data
  end

      -- Client: MATCH name version

      -- SERVER: REPLY version hash

  function upstream.read(name, version)
    remote.writeAs("read", name .. " " .. version)
    return remote.readAs("reply")
  end



  function upstream.claim(request)
    remote.writeAs("claim", request)
    return remote.readAs("reply")
  end

  function upstream.share(request)
    remote.writeAs("share", request)
    return remote.readAs("reply")
  end

  function upstream.unclaim(request)
    remote.writeAs("unclaim", request)
    return remote.readAs("reply")
  end

  return upstream

end

