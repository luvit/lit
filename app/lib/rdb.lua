local uv = require('uv')
local semver = require('semver')
local log = require('./log')
local connect = require('coro-tcp').connect
local httpCodec = require('http-codec')
local websocketCodec = require('websocket-codec')
local makeRemote = require('./codec').makeRemote
local wrapper = require('./wrapper')
local readWrap, writeWrap = wrapper.reader, wrapper.writer
local tlsWrap = require('coro-tls').wrap

local function connectRemote(url)
  local protocol, host, port, path = string.match(url, "^(wss?)://([^:/]+):?(%d*)(/?[^#]*)")
  local tls
  if protocol == "ws" then
    port = tonumber(port) or 80
    tls = false
  elseif protocol == "wss" then
    port = tonumber(port) or 443
    tls = true
  else
    error("Sorry, only ws:// or wss:// protocols supported")
  end
  if #path == 0 then path = "/" end

  local rawRead, rawWrite, socket = assert(connect(host, port))
  if tls then
    rawRead, rawWrite = tlsWrap(rawRead, rawWrite)
  end
  local read, updateDecoder = readWrap(rawRead, httpCodec.decoder())
  local write, updateEncoder = writeWrap(rawWrite, httpCodec.encoder())

  -- Perform the websocket handshake
  assert(websocketCodec.handshake({
    host = host,
    path = path,
    protocol = "lit"
  }, function (req)
    write(req)
    local res = read()
    if not res then error("Missing server response") end
    if res.code == 400 then
      p { req = req, res = res }
      local reason = read() or res.reason
      error("Invalid request: " .. reason)
    end
    return res
  end))

  -- Upgrade the protocol to websocket
  updateDecoder(websocketCodec.decode)
  updateEncoder(websocketCodec.encode)

  return socket, makeRemote(read, write, true)
end

return function(db, url)

  -- Implement very basic connection keepalive using an uv_idle timer
  -- This will disconnect very quickly if a connect() isn't called
  -- soon after a disconnect()
  local timeout, remote, socket
  local function connect()
    if remote then
      timeout:stop()
    else
      log("connecting", url)
      socket, remote = connectRemote(url)
      timeout = uv.new_timer()
    end
  end
  local function close()
    if remote then
      -- log("disconnecting", url)
      socket:close()
      timeout:close()
      timeout = nil
      remote = nil
      socket = nil
    end
  end
  local function disconnect()
    timeout:start(10, 0, close)
  end

  function db.readRemote(author, name, version)
    local tag = author .. "/" .. name
    connect()
    local query = version and (tag .. " " .. version) or tag
    remote.writeAs("read", query)
    local data = remote.readAs("reply")
    disconnect()
    return data
  end

  local rawMatch = db.match
  function db.match(author, name, version)
    local match, hash = rawMatch(author, name, version)
    local tag = author .. "/" .. name
    connect()
    local query = version and (tag .. " " .. version) or tag
    log("matching", query)
    remote.writeAs("match", query)
    local data = remote.readAs("reply")
    disconnect()
    local upMatch, upHash
    if data then
      upMatch, upHash = string.match(data, "^([^ ]+) (.*)$")
    end
    if semver.gte(match, upMatch) then
      return match, hash
    end
    return upMatch, upHash
  end

  local rawLoad = db.load
  function db.load(hash)
    local raw = rawLoad(hash)
    if raw then return raw end
    db.fetch({hash})
    return assert(rawLoad(hash))
  end

  function db.fetch(list)
    local refs = {}
    repeat
      local hashes = list
      list = {}
      -- Fetch any hashes from list we don't have already
      local wants = {}
      local pending = {}
      for i = 1, #hashes do
        local hash = hashes[i]
        if not pending[hash] and not db.has(hash) then
          wants[#wants + 1] = hash
          pending[hash] = true
        end
      end
      if #wants > 0 then
        log("fetching", #wants .. " object" .. (#wants == 1 and "" or "s"))
        connect()
        remote.writeAs("wants", wants)
        for i = 1, #wants do
          local hash = wants[i]
          assert(db.save(remote.readAs("send")) == hash, "hash mismatch in result object")
        end
        disconnect()
      end

      -- Process the hashes looking for child nodes
      for i = 1, #hashes do
        local hash = hashes[i]
        local kind, value = db.loadAny(hash)
        if kind == "tag" then
          -- TODO: verify tag
          refs[value.tag] = hash
          table.insert(list, value.object)
        elseif kind == "tree" then
          for i = 1, #value do
            local subHash = value[i].hash
            table.insert(list, subHash)
          end
        end
      end
    until #list == 0
    for ref, hash in pairs(refs) do
      local author, name, version = string.match(ref, "^([^/]+)/(.*)/v(.*)$")
      db.write(author, name, version, hash)
    end
    return refs
  end

  function db.push(hash)
    connect();
    remote.writeAs("send", db.load(hash))
    while true do
      local name, data = remote.read()
      if name == "wants" then
        for i = 1, #data do
          remote.writeAs("send", db.load(data[i]))
        end
      elseif name == "done" then
        return data
      else
        error("Expected more wants or done in reply to send to server")
      end
    end
    disconnect();
  end

  function db.upquery(name, request)
    connect();
    remote.writeAs(name, request)
    local reply, err = remote.readAs("reply")
    disconnect()
    return reply, err
  end

  return db
end
