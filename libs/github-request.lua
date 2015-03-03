local env = require('env')
local log = require('./log')
local jsonParse = require('json').parse
local http = require('coro-http')

return function (path, etag)
  local url = "https://api.github.com" .. path
  log("github request", url)

  local headers = {
    {"User-Agent", "lit"},
  }

  -- Set GITHUB_TOKEN to a token from https://github.com/settings/tokens/new to increase the rate limit
  local token = env.get("GITHUB_TOKEN")
  if token then
    headers[#headers + 1] = {"Authorization", "token " .. token}
  end

  if etag then
    headers[#headers + 1] = {"If-None-Match", etag}
  end

  local head, json = http.request("GET", url, headers)

  json = jsonParse(json) or json
  return head, json, url
end

