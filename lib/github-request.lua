local env = require('env')
local httpCodec = require('http-codec')
local connect = require('coro-tcp').connect
local tlsWrap = require('coro-tls').wrap
local wrapper = require('./wrapper')
local log = require('./log')
local jsonParse = require('json').parse

return function (path, etag)
  local url = "https://api.github.com" .. path
  log("github request", url)

  local req = {
    method = "GET",
    path = path,
    {"Host", "api.github.com"},
    {"User-Agent", "lit"},
  }

  -- Set GITHUB_TOKEN to a token from https://github.com/settings/tokens/new to increase the rate limit
  local token = env.get("GITHUB_TOKEN")
  if token then
    req[#req + 1] = {"Authorization", "token " .. token}
  end

  if etag then
    req[#req + 1] = {"If-None-Match", etag}
  end

  local read, write = assert(connect("api.github.com", "https"))
  read, write = tlsWrap(read, write)

  read = wrapper.reader(read, httpCodec.decoder())
  write = wrapper.writer(write, httpCodec.encoder())

  write(req)
  local head = read()
  local json = {}
  for item in read do
    if #item == 0 then break end
    json[#json + 1] = item
  end
  write()
  json = table.concat(json)
  json = jsonParse(json) or json
  return head, json, url
end

