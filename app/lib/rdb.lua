local uv = require('uv')
local semver = require('semver')
local git = require('git')
local deframe = git.deframe
local decoders = git.decoders
local openssl = require('openssl')
local log = require('./log')
local digest = openssl.digest.digest
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
  local timeout = uv.new_timer()
  local remote, socket
  local function connect()
    uv.timer_stop(timeout)
    if not remote then
      log("connecting", url)
      socket, remote = connectRemote(url)
    end
  end
  local function close()
    uv.timer_stop(timeout)
    if remote then
      log("disconnecting", url)
      socket:close()
      remote = nil
      socket = nil
    end
  end
  local function disconnect()
    uv.timer_start(timeout, 100, 0, close)
  end

  local rawMatch = db.match
  function db.match(author, tag, version)
    local match, hash = rawMatch(author, tag, version)
    local name = author .. "/" .. tag
    connect()
    remote.writeAs("match", version and (name .. " " .. version) or name)
    local data = remote.readAs("reply")
    disconnect()
    local upMatch, upHash
    if data then
      upMatch, upHash = string.match(data, "^([^ ]+) (.*)$")
    end
    if semver.gte(match, upMatch) then
      return match, hash
    end
    log("fetching", author .. '/' .. tag .. '@' .. upMatch)
    return upMatch, upHash
  end

  local rawLoad = db.load
  function db.load(hash)
    local kind, value = rawLoad(hash)
    if kind then return kind, value end
    connect()
    remote.writeAs("wants", {hash})
    kind, value = deframe(remote.readAs("send"))
    disconnect()
    assert(db.save(kind, value) == hash)
    value = decoders[kind](value)
    if kind == "tag" then
      local author, name, version = string.match(value.tag, "^([^/]+)/(.*)/v(.*)$")
      db.write(author, name, version, hash)
    end
    return kind, value
  end

  function db.fetch(list)
    local refs = {}
    connect()
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
        log("fetching", #wants .. " inner objects")
        remote.writeAs("wants", wants)
        for i = 1, #wants do
          local hash = wants[i]
          local kind, value = deframe(remote.readAs("send"))
          assert(db.save(kind, value) == hash, "hash mismatch in result object")
        end
      end

      -- Process the hashes looking for child nodes
      for i = 1, #hashes do
        local hash = hashes[i]
        local kind, value = db.load(hash)
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
    disconnect()
    for ref, hash in pairs(refs) do
      local author, name, version = string.match(ref, "^([^/]+)/(.*)/v(.*)$")
      db.write(author, name, version, hash)
    end
    return refs
  end

  return db
end
