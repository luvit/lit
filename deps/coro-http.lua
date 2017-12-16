--[[lit-meta
  name = "creationix/coro-http"
  version = "3.0.0"
  dependencies = {
    "creationix/coro-net@3.0.0",
    "luvit/http-codec@3.0.0"
  }
  homepage = "https://github.com/luvit/lit/blob/master/deps/coro-http.lua"
  description = "An coro style http(s) client and server helper."
  tags = {"coro", "http"}
  license = "MIT"
  author = { name = "Tim Caswell" }
]]

local httpCodec = require('http-codec')
local net = require('coro-net')

local function createServer(host, port, onConnect)
  net.createServer({
    host = host,
    port = port,
    encode = httpCodec.encoder(),
    decode = httpCodec.decoder(),
  }, function (read, write, socket)
    for head in read do
      local parts = {}
      for part in read do
        if #part > 0 then
          parts[#parts + 1] = part
        else
          break
        end
      end
      local body = table.concat(parts)
      head, body = onConnect(head, body, socket)
      write(head)
      if body then write(body) end
      write("")
      if not head.keepAlive then break end
    end
  end)
end

local function parseUrl(url)
  local protocol, host, hostname, port, path = url:match("^(https?:)//(([^/:]+):?([0-9]*))(/?.*)$")
  if not protocol then error("Not a valid http url: " .. url) end
  local tls = protocol == "https:"
  port = port and tonumber(port) or (tls and 443 or 80)
  if path == "" then path = "/" end
  return {
    tls = tls,
    host = host,
    hostname = hostname,
    port = port,
    path = path
  }
end

local connections = {}

local function getConnection(host, port, tls, timeout)
  for i = #connections, 1, -1 do
    local connection = connections[i]
    if connection.host == host and connection.port == port and connection.tls == tls then
      table.remove(connections, i)
      -- Make sure the connection is still alive before reusing it.
      if not connection.socket:is_closing() then
        connection.reused = true
        connection.socket:ref()
        return connection
      end
    end
  end
  local read, write, socket, updateDecoder, updateEncoder = assert(net.connect {
    host = host,
    port = port,
    tls = tls,
    timeout = timeout,
    encode = httpCodec.encoder(),
    decode = httpCodec.decoder()
  })
  return {
    socket = socket,
    host = host,
    port = port,
    tls = tls,
    read = read,
    write = write,
    updateEncoder = updateEncoder,
    updateDecoder = updateDecoder,
    reset = function ()
      -- This is called after parsing the response head from a HEAD request.
      -- If you forget, the codec might hang waiting for a body that doesn't exist.
      updateDecoder(httpCodec.decoder())
    end
  }
end

local function saveConnection(connection)
  if connection.socket:is_closing() then return end
  connections[#connections + 1] = connection
  connection.socket:unref()
end

local function request(method, url, headers, body, timeout)
  local uri = parseUrl(url)
  local connection = getConnection(uri.hostname, uri.port, uri.tls, timeout)
  local read = connection.read
  local write = connection.write

  local req = {
    method = method,
    path = uri.path,
    {"Host", uri.host}
  }
  local contentLength
  local chunked
  if headers then
    for i = 1, #headers do
      local key, value = unpack(headers[i])
      key = key:lower()
      if key == "content-length" then
        contentLength = value
      elseif key == "content-encoding" and value:lower() == "chunked" then
        chunked = true
      end
      req[#req + 1] = headers[i]
    end
  end

  if type(body) == "string" then
    if not chunked and not contentLength then
      req[#req + 1] = {"Content-Length", #body}
    end
  end

  write(req)
  if body then write(body) end
  local res = read()
  if not res then
    if not connection.socket:is_closing() then
      connection.socket:close()
    end
    -- If we get an immediate close on a reused socket, try again with a new socket.
    -- TODO: think about if this could resend requests with side effects and cause
    -- them to double execute in the remote server.
    if connection.reused then
      return request(method, url, headers, body)
    end
    error("Connection closed")
  end

  body = {}
  if req.method == "HEAD" then
    connection.reset()
  else
    while true do
      local item = read()
      if not item then
        res.keepAlive = false
        break
      end
      if #item == 0 then
        break
      end
      body[#body + 1] = item
    end
  end

  if res.keepAlive then
    saveConnection(connection)
  else
    write()
  end

  -- Follow redirects
  if method == "GET" and (res.code == 302 or res.code == 307) then
    for i = 1, #res do
      local key, location = unpack(res[i])
      if key:lower() == "location" then
        headers = headers or {}
        headers.redirects = headers.redirects or {}
        table.insert(headers.redirects, location)
        return request(method, location, headers)
      end
    end
  end

  res.redirects = headers and headers.redirects or {}
  res.url = url

  return res, table.concat(body)
end

return {
  createServer = createServer,
  parseUrl = parseUrl,
  getConnection = getConnection,
  saveConnection = saveConnection,
  request = request,
}
