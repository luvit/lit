--[[
REST API
========

This is a simple rest API for reading the remote database over HTTP.
It uses hypermedia in the JSON responses to make linking between requests simple.

GET / -> api json {
  blobs = "/blobs/{hash}"
  trees = "/trees/{hash}"
  packages = "/packages{/author}{/tag}{/version}"
}
GET /blobs/$HASH -> raw data
GET /trees/$HASH -> tree json {
 foo = { mode = 0644, hash = "...", url="/blobs/..." }
 bar = { mode = 0755, hash = "...", url="/trees/..." }
 ...
}
GET /packages -> authors json {
  creationix = "/packages/creationix"
  ...
}
GET /packages/$AUTHOR -> tags json {
  git = "/packages/creationix/git"
  ...
}
GET /packages/$AUTHOR/$TAG -> versions json {
  v0.1.2 = "/packages/creationix/git/v0.1.2"
  ...
}
GET /packages/$AUTHOR/$TAG/$VERSION -> tag json {
  hash = "..."
  object = "..."
  url = "/trees/..."
  type = "tree"
  tag = "v0.2.3"
  tagger = {
    name = "Tim Caswell",
    email = "tim@creationix.com",
    date = {
      seconds = 1423760148
      offset = -0600
    }
  }
  message = "..."
}

GET /search/$query -> list of matches

]]

local pathJoin = require('luvi').path.join
local digest = require('openssl').digest.digest
local date = require('os').date
local jsonStringify = require('json').stringify
local jsonParse = require('json').parse
local core = require('./autocore')
local db = core.db
local modes = require('git').modes

return function (prefix)

  local function makeUrl(kind, hash, filename)
    return prefix .. "/" .. kind .. "s/" .. hash .. '/' .. filename
  end

  local routes = {
    "^/blobs/([0-9a-f]+)/(.*)", function (hash, path)
      local body = db.loadAs("blob", hash)
      local filename = path:match("[^/]+$")
      return body, {
        {"Content-Disposition", "attachment; filename=" .. filename}
      }
    end,
    "^/trees/([0-9a-f]+)/(.*)", function (hash, filename)
      local tree = db.loadAs("tree", hash)
      for i = 1, #tree do
        local entry = tree[i]
        tree[i].url = makeUrl(modes.toType(entry.mode), entry.hash, filename .. '/' .. entry.name)
      end
      return tree
    end,
    "^/$", function ()
      return  {
        blobs = prefix .. "/blobs/{hash}",
        trees = prefix .. "/trees/{hash}",
        authors = prefix .. "/packages",
        names = prefix .. "/packages{/author}",
        versions = prefix .. "/packages{/author}{/name}",
        package = prefix .. "/packages{/author}{/name}{/version}",
        search = prefix .. "/search{/query}",
      }
    end,
    "^/packages/([^/]+)/(.+)/v([^/]+)$", function (author, name, version)
      local hash = db.read(author, name, version)
      local tag = db.loadAs('tag', hash)
      local filename = author .. "/" .. name .. "-v" .. version
      if tag.type == "blob" then
        filename = filename .. ".lua"
      end
      tag.hash = hash
      tag.url = makeUrl(tag.type, tag.object, filename)
      return tag
    end,
    "^/packages/([^/]+)/(.+)$", function (author, name)
      local versions = {}
      for version in db.versions(author, name) do
        versions[version] = prefix .. "/packages/" .. author .. "/" .. name .. "/v" .. version
      end
      return next(versions) and versions
    end,
    "^/packages/([^/]+)$", function (author)
      local names = {}
      for name in db.names(author) do
        names[name] = prefix .. "/packages/" .. author .. "/" .. name
      end
      return next(names) and names
    end,
    "^/packages$", function ()
      local authors = {}
      for author in db.authors() do
        authors[author] =  prefix .. "/packages/" .. author
      end
      return next(authors) and authors
    end,
    "^/search/(.*)$", function (query)
      local matches = {}
      for author in db.authors() do
        if author:match(query) then
          matches[#matches + 1] = {
            type = "author",
            name = author,
            url = prefix .. "/packages/" .. author
          }
        end
        for name in db.names(author) do
          if name:match(query) then
            local version, hash = db.match(author, name)
            local tag = db.loadAs("tag", hash)
            local meta = tag.message:match("%b{}")
            if meta then
              meta = jsonParse(meta)
            else
              meta = {}
            end
            meta.type = "package"
            meta.url = prefix .. "/packages/" .. author .. "/" .. name .. "/v" .. version
            meta.version = version
            meta.tagger = tag.tagger
            matches[author .. "/" .. name] = meta
          end
        end
      end
      return {
        query = query,
        matches = matches,
      }
    end
  }

  return function (req)
    if not (req.method == "GET" or req.method == "HEAD") then
      return nil, "Must be GET or HEAD"
    end
    local path = pathJoin(req.path)
    local headers = {}
    for i = 1, #req do
      local key, value = unpack(req[i])
      headers[key:lower()] = value
    end
    if not prefix then
      prefix = "http://" .. headers.host
    end
    local body, extra
    for i = 1, #routes, 2 do
      local match = {path:match(routes[i])}
      if #match > 0 then
        body, extra = routes[i + 1](unpack(match))
        break
      end
    end

    if not body then
      return {code = 404}
    end
    local res = {
      code = 200,
      {"Date", date("!%a, %d %b %Y %H:%M:%S GMT")},
      {"Server", "lit"},
    }
    if extra then
      for i = 1, #extra do
        res[#res + 1] = extra[i]
      end
    end
    if type(body) == "table" then
      body = jsonStringify(body) .. "\n"
      res[#res + 1] = {"Content-Type", "application/json"}
    end
    res.body = body

    local etag = string.format('"%s"', digest("sha1", body))
    res[#res + 1] = {"ETag", etag}
    res[#res + 1] = {"Content-Length", #body}

    if headers["if-none-match"] == etag then
      res.code = 304
      res.body = ""
    end
    if req.method == "HEAD" then
      res.body = ""
    end

    return res
  end
end
