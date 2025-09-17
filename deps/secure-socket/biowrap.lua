--[[

Copyright 2016 The Luvit Authors. All Rights Reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS-IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

--]]
local openssl = require("openssl")
local uv = require("uv")

local BIO_BUFFER_SIZE = 8192
local PEEK_LENGTH = 1

local function closeSocket(socket)
  if not socket:is_closing() then
    socket:close()
  end
end

local function wrapSocketMethod(socket, method)
  return function(_, ...)
    return method(socket, ...)
  end
end

-- Flush the bout buffer into the wrapped socket
-- i.e. send the encrypted data
local function flushSecureSocket(ssocket, callback)
  local chunks = {}
  local i = 0
  while ssocket.bout:pending() > 0 do
    i = i + 1
    chunks[i] = ssocket.bout:read()
  end
  if i == 0 then
    if callback then callback() end
    return true
  end
  return ssocket.handle:write(chunks, callback)
end

local function readIncoming(ssocket)
  if not ssocket.onPlain then
    return
  end
  while true do
    -- TODO: handle read errors and shutdowns
    local plain = ssocket.ssl:read()
    if not plain then break end
    ssocket.onPlain(nil, plain)
  end
end

---@param socket uv_stream_t
---@param ctx ssl_ctx
---@param options? {server: boolean?, servername: string?}
local function newSecureSocket(socket, ctx, options)
  options = options or {}
  local ssocket = {
    handle = socket,    -- the wrapped stream
    tls = true,         -- distinguish secure sockets from normal ones
    connected = false,  -- whether the handshake & verification is done and we're ready for data

    isServer = options.server,        -- whether we're talking to a server (peer is a server)
    servername = options.servername,  -- the name of the server we're talking to (domain) if any

    bin = openssl.bio.mem(BIO_BUFFER_SIZE),  -- bio input buffer
    bout = openssl.bio.mem(BIO_BUFFER_SIZE), -- bio output buffer

    ssl = nil,                  -- the SSL session object
    onPlain = nil,              -- the reader assigned for the incoming decrypted stream
    onCipher = nil,             -- the reader assigned for the incoming encrypted stream
    onHandshakeComplete = nil,  -- called when the handshake exchange is done
  }

  ssocket.ssl = ctx:ssl(ssocket.bin, ssocket.bout, ssocket.isServer)

  -- When requested to start reading, start the real socket and setup
  -- the onPlain handler
  function ssocket.read_start(_, onRead)
    ssocket.onPlain = onRead
    local success, err = socket:read_start(ssocket.onCipher)
    -- if we have data already available read it, see #341.
    -- we have to delay the callback to the next tick after we return
    -- so the caller has a chance to handle incoming data.
    if success then
      if ssocket.connected and ssocket.ssl:peek(PEEK_LENGTH) then
        uv.new_timer():start(0, 0, function()
          readIncoming(ssocket)
        end)
      end
    end
    return success, err
  end

  -- When requested to write plain data, encrypt it and write to socket
  function ssocket.write(_, plain, callback)
    ssocket.ssl:write(plain) -- TODO: handle write errors
    return flushSecureSocket(ssocket, callback)
  end

  -- Make the wrapped stream methods available
  -- the result methods doesn't depend on `self`
  setmetatable(ssocket, {
    __index = function(t, k)
      local ov = rawget(t, k)
      local tsocket = rawget(t, "handle")
      if not ov and tsocket and tsocket[k] ~= nil then
        if type(tsocket[k]) == "function" then
          return wrapSocketMethod(tsocket, tsocket[k])
        else
          return tsocket[k]
        end
      else
        return ov
      end
    end
  })

  return ssocket
end

local function doPeerVerification(ssocket)
  local success, result = ssocket.ssl:getpeerverification()
  if not success and result then
    for i=1, #result do
      if not result[i].preverify_ok then
        closeSocket(ssocket.handle)
        return nil, "Error verifying peer: " .. result[i].error_string
      end
    end
  else
    return true, result
  end
end

local function doPeerCertValidation(ssocket)
  local cert = ssocket.ssl:peer()
  if not cert then
    return nil, "The peer did not provide a certificate"
  end
  if not cert:check_host(ssocket.servername) then
    return nil, "The server hostname does not match the certificate's domain"
  end
  return true
end

local function doHandshake(ssocket)
  -- TODO: optimize handshakes by implementing sessions
  -- TODO: handle handshake errors properly and reattempt handshake when requested to
  if not ssocket.ssl:handshake() then
    return flushSecureSocket(ssocket)
  end

  ssocket.handle:read_stop()
  local success, result = doPeerVerification(ssocket)
  if not success then
    closeSocket(ssocket.handle)
    return ssocket.onHandshakeComplete(result)
  end

  if not ssocket.isServer then
    success, result = doPeerCertValidation(ssocket)
    if not success then
      closeSocket(ssocket.handle)
      return ssocket.onHandshakeComplete(result)
    end
  end
  ssocket.connected = true

  return ssocket.onHandshakeComplete(nil, ssocket)
end

---@param ctx ssl_ctx
---@param socket uv_stream_t
---@param options {server: boolean?, servername: string?}
---@param handshakeComplete function # called when the handshake is complete and it's safe
return function (ctx, socket, options, handshakeComplete)
  local ssocket = newSecureSocket(socket, ctx, options)
  ssocket.onHandshakeComplete = handshakeComplete

  if not options.server and options.servername then
    ssocket.ssl:set("hostname", options.servername)
  end

  local function onCipher(err, data)
    if not ssocket.connected then
      if err or not data then
        return handshakeComplete(err or "Peer aborted the SSL handshake", data)
      end
      ssocket.bin:write(data)
      return doHandshake(ssocket)
    end
    if err or not data then
      return ssocket.onPlain(err, data)
    end
    ssocket.bin:write(data)
    readIncoming(ssocket)
  end
  ssocket.onCipher = onCipher

  doHandshake(ssocket)
  socket:read_start(onCipher)
end
