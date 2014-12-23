local uv = require('uv')
local digest = require('openssl').digest.digest
local codec = require('./codec')

local function makeCallback()
  local thread = coroutine.running()
  return function (err, data)
    if err then
      return assert(coroutine.resume(thread, nil, err))
    end
    return assert(coroutine.resume(thread, data or true))
  end
end

local function connect(host, port)
  local res, success, err
  uv.getaddrinfo(host, port, { socktype = "stream" }, makeCallback())
  res, err = coroutine.yield()
  if not res then return nil, err end
  local socket = uv.new_tcp()
  socket:connect(res[1].addr, res[1].port, makeCallback())
  success, err = coroutine.yield()
  if not success then return nil, err end
  return socket
end

return function (storage, host, port)
  local socket, err = connect(host, port or 4821)
  if not socket then return nil, err end

  local read, write = codec(false, socket)

  local callbacks = {}
  local waiting

  -- Handshake with the remote server
  write("handshake", {0})
  local command, data = read()
  -- Make sure the server is speaking protocol v0
  assert(command == "agreement" and data == 0)

  coroutine.wrap(xpcall)(function ()
    for command, data in read do
      if command == "reply" and waiting then
        local thread = waiting
        waiting = nil
        assert(coroutine.resume(thread, data))
      elseif command == "error" and waiting then
        local thread = waiting
        waiting = nil
        assert(coroutine.resume(thread, nil, data))
      elseif command == "want" then
        write("send", storage.load(data))
      elseif command == "send" then
        local hash = digest("sha1", data)
        local callback = callbacks[hash]
        assert(callback, "Unexpected value sent!")
        callbacks[hash] = nil
        callback(nil, data)
      else
        p(command, data)
      end
    end
  end, function (message)
    error(debug.traceback(message))
  end)

  local upstream = {}

  --[[
  upstream.push(name, version) -> hash
  --------------------------

  Push a ref and dependents recursivly to upstream server.

  Internally this does the following:

      Client: SEND tagObject

      Server: WANT objectHash

      Client: SEND object

      Server: WANT ...
      Server: WANT ...
      Server: WANT ...

      Client: SEND ...
      Client: SEND ...
      Client: SEND ...

      Server: CONF tagHash

  The client sends an unwanted tag which will trigger a sync from the server.
  The client, without waiting also sends a VERIFY request requesting the server
  tell it when it has the tag and it's children.  The server then fetches and
  objects it's missing.  When done, server confirms tagHash to the client.

  If a server already has an object when receiving a graph, it will scan it's
  children for missing bits from previous failed attemps and resume there.

  Only after confirming the entire tree saved will the server write the tag and
  seal the package.
  ]]--
  function upstream.push(ref)
    error("TODO: upstream.push")
    return hash
  end

  --[[
  upstream.pull(hash) -> success, err
  --------------------------

  Pull a hash and dependents recursivly from upstream server.

  This is essentially the same command, but reversed.

      Client: WANT tagHash

      Server: SEND tagObject

      Client: WANT objectHash

      Server: SEND object

      Client: WANT ...
      Client: WANT ...
      Client: WANT ...

      Server: SEND ...
      Server: SEND ...
      Server: SEND ...

  The client knows locally when it has the entire tree and creates the local tag
  sealing the package.  The client will also check deep for missing objects
  before confirming a tree as complete.
  ]]--
  function upstream.pull(hash)
    error("TODO: upstream.pull")
    return name, version
  end

  --[[
  upstream.match(name, version) -> version, hash
  ----------------------------------------------

  Query a server for the best match to a semver

      Client: MATCH name version

      Server: REPLY version
  ]]--
  function upstream.match(name, version)
    error("TODO: upstream.match")
    return version, hash
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

