exports.name = "creationix/coro-http"
exports.version = "1.1.1"
exports.dependencies = {
  "creationix/coro-net@1.1.1",
  "creationix/coro-tls@1.2.0",
  "creationix/coro-wrapper@1.0.0",
  "luvit/http-codec@1.0.0"
}
exports.homepage = "https://github.com/luvit/lit/blob/master/deps/coro-http.lua"
exports.description = "An coro style http(s) client and server helper."
exports.tags = {"coro", "http"}
exports.license = "MIT"
exports.author = { name = "Tim Caswell" }

local httpCodec = require('http-codec')
local net = require('coro-net')
local connect = net.connect
local createServer = net.createServer
local tlsWrap = require('coro-tls').wrap
local wrapper = require('coro-wrapper')

function exports.createServer(host, port, onConnect)
  createServer({host=host,port=port}, function (rawRead, rawWrite, socket)
    local read = wrapper.reader(rawRead, httpCodec.decoder())
    local write = wrapper.writer(rawWrite, httpCodec.encoder())
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
exports.parseUrl = parseUrl

local connections = {}

local function getConnection(host, port, tls)
  for i = #connections, 1, -1 do
    local connection = connections[i]
    if connection.host == host and connection.port == port and connection.tls == tls then
      table.remove(connections, i)
      -- Make sure the connection is still alive before reusing it.
      if not connection.socket:is_closing() then
        return connection
      end
    end
  end
  local read, write, socket = assert(connect({host=host,port=port}))
  if tls then
    read, write = tlsWrap(read, write)
  end
  return {
    socket = socket,
    host = host,
    port = port,
    tls = tls,
    read = wrapper.reader(read, httpCodec.decoder()),
    write = wrapper.writer(write, httpCodec.encoder()),
  }
end
exports.getConnection = getConnection

local function saveConnection(connection)
  if connection.socket:is_closing() then return end
  connections[#connections + 1] = connection
end
exports.saveConnection = saveConnection

function exports.request(method, url, headers, body)
  local uri = parseUrl(url)
  local connection = getConnection(uri.hostname, uri.port, uri.tls)
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
  if not res then error("Connection closed") end

  body = {}
  repeat
    local item = read()
    if not item then
      res.keepAlive = false
      break
    end
    if #item == 0 then break end
    body[#body + 1] = item
  until false

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
        return exports.request(method, location, headers)
      end
    end
  end

  return res, table.concat(body)
end
