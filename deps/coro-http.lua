exports.name = "creationix/coro-http"
exports.version = "1.0.0"
exports.dependencies = {
  "creationix/coro-tcp@1.0.4",
  "creationix/coro-tls@1.1.1",
  "creationix/coro-wrapper@1.0.0",
  "luvit/http-codec@1.0.0"
}

local httpCodec = require('http-codec')
local connect = require('coro-tcp').connect
local tlsWrap = require('coro-tls').wrap
local wrapper = require('coro-wrapper')

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
      table.remove(connection, i)
      return connection
    end
  end
  local read, write = assert(connect(host, port))
  if tls then
    read, write = tlsWrap(read, write)
  end
  -- TODO: wrap read and write to clean up when socket terminates?
  return {
    host = host,
    port = port,
    tls = tls,
    read = wrapper.reader(read, httpCodec.decoder()),
    write = wrapper.writer(write, httpCodec.encoder()),
  }
end
exports.getConnection = getConnection

local function saveConnection(connection)
  -- TODO: add some idle timeout or timestamp?
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
  if headers then
    for i = 1, #headers do
      req[#req + 1] = headers[i]
    end
  end

  write(req)
  if body then write(body) end
  local res = read()
  body = {}
  for item in read do
    if #item == 0 then break end
    body[#body + 1] = item
  end

  if res.keepAlive then
    saveConnection(connection)
  else
    write()
  end

  -- Follow redirects
  if method == "GET" and res.code == 302 then
    for i = 1, #res do
      local key, location = unpack(res[i])
      if key:lower() == "location" then
        return exports.request(method, location, headers)
      end
    end
  end

  return res, table.concat(body)
end
