--[[
REST API
========

This is a simple rest API for reading the remote database over HTTP.
It uses hypermedia in the JSON responses to make linking between requests simple.

GET / -> api json {
  blobs = "/blobs/{hash}"
  trees = "/trees/{hash}"
  packages = "/packages{/author}{/tag}{/version}"
  ...
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
  tag = "author/package/v0.2.3"
  keywords = {"..."}
  description = "..."
  author = {name="...", url="...", email="..."}
  dependencies = {"author/package@v1.0.0"}
  version = "0.2.3"
  homepage = "..."
  tagger = {
    name = "Tim Caswell",
    email = "tim@creationix.com",
    date = {
      seconds = 1423760148
      offset = -0600
    }
  }
}

GET /search/$QUERY -> packages/authors json {
  query = "..."
  matches = {
    {
      type = "package"
      url = "/packages/author/package/v0.2.3"
      hash = "..."
      object = "..."
      tag = "author/package/v0.2.3"
      keywords = {"..."}
      description = "..."
      author = {name="...", url="...", email="..."}
      dependencies = {"author/package@v1.0.0"}
      version = "0.2.3"
      homepage = "..."
      tagger = {
        name = "Tim Caswell",
        email = "tim@creationix.com",
        date = {
          seconds = 1423760148
          offset = -0600
        }
      }
    },
    {
      type = "author"
      url = "/packages/author"
    },
    ...
  }
}

Possible search queries:
  "*"        = All authors and packages
  "*/"       = All authors
  "/*"       = All packages
  "author/"   = All packages of the author (if the author name is an exact match)
  "author/"   = All authors that partially match the author query (if no exact matches were found)
  "/package"  = All packages that match the package query
  "query"     = All packages or authors that match the query

]]

local digest = require('openssl').digest.digest
local date = require('os').date
local jsonStringify = require('json').stringify
local jsonParse = require('json').parse
local core = require('./autocore')
local db = core.db
local modes = require('git').modes


local litVersion = "Lit " .. require('../package').version

local function hex_to_char(x)
  return string.char(tonumber(x, 16))
end

local function unescape(url)
  return url:gsub("%%(%x%x)", hex_to_char)
end

local function combineTables(...)
  local merged = {}
  for _,t in ipairs({...}) do
    for k,v in pairs(t) do merged[k] = v end
  end
  return merged
end

return function (prefix)

  local function makeUrl(kind, hash, filename)
    return prefix .. "/" .. kind .. "s/" .. hash .. '/' .. filename
  end

  local function getMetadataOfHash(hash)
    local tag = db.loadAs("tag", hash)
    local meta = tag.message:match("%b{}")
    if meta then
      meta = jsonParse(meta)
    else
      meta = {}
    end
    meta = combineTables(tag, meta)
    meta.message = nil
    meta.hash = hash
    return meta
  end

  local routes = {
    "^/blobs/([0-9a-f]+)/(.*)", function (hash, path)
      local body = db.loadAs("blob", hash)
      local filename = path:match("([^/]+)/*$")
      return body, {
        {"Content-Disposition", "attachment; filename=" .. filename}
      }
    end,
    "^/trees/([0-9a-f]+)/(.-)/?$", function (hash, filename)
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
        names = prefix .. "/packages/{author}",
        versions = prefix .. "/packages/{author}/{name}",
        package = prefix .. "/packages/{author}/{name}/{version}",
        search = prefix .. "/search/{query}",
      }
    end,
    "^/packages/([^/]+)/(.+)/v([^/]+)/?$", function (author, name, version)
      local hash = db.read(author, name, version)
      local meta = getMetadataOfHash(hash)
      local filename = author .. "/" .. name .. "-v" .. version
      if meta.type == "blob" then
        filename = filename .. ".lua"
      end
      meta.url = makeUrl(meta.type, meta.object, filename)
      return meta
    end,
    "^/packages/([^/]+)/([^/]+)/?$", function (author, name)
      local versions = {}
      for version in db.versions(author, name) do
        versions[version] = prefix .. "/packages/" .. author .. "/" .. name .. "/v" .. version
      end
      return next(versions) and versions
    end,
    "^/packages/([^/]+)/?$", function (author)
      local names = {}
      for name in db.names(author) do
        names[name] = prefix .. "/packages/" .. author .. "/" .. name
      end
      return next(names) and names
    end,
    "^/packages/?$", function ()
      local authors = {}
      for author in db.authors() do
        authors[author] =  prefix .. "/packages/" .. author
      end
      return next(authors) and authors
    end,
    "^/search/(.*)$", function (query)
      -- escape all special pattern characters except *
      query = query:gsub("[%(%)%%%+%-%?%[%]%^%$%.]", function(c) return "%" .. c end)
      -- expand * to .* for a glob-like wildcard
      query = query:gsub("%*", ".*")
      local matches = {}
      local authorQuery, separator, packageQuery = query:match("^(.-)(/?)([^/]*)$")
      if authorQuery == "" then authorQuery = nil end
      if packageQuery == "" then packageQuery = nil end
      local hadSeparator = separator ~= ""
      for author in db.authors() do
        local authorMatchesExactly = authorQuery == author
        local authorMatches = authorQuery and author:match(authorQuery)
        if (not packageQuery and authorMatches and not authorMatchesExactly and hadSeparator) or (not hadSeparator and not authorQuery and author:match(packageQuery)) then
          matches[author] = {
            type = "author",
            url = prefix .. "/packages/" .. author
          }
        end
        if (authorMatches and packageQuery) or not authorQuery or (not packageQuery and authorMatchesExactly and hadSeparator) then
          for name in db.names(author) do
            if not packageQuery or (packageQuery and name:match(packageQuery)) then
              local version, hash = db.match(author, name)
              local meta = getMetadataOfHash(hash)
              meta.type = "package"
              meta.version = version
              meta.url = prefix .. "/packages/" .. author .. "/" .. name .. "/v" .. version
              matches[author .. "/" .. name] = meta
            end
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

    if req.method == "OPTIONS" then
      -- Wide open CORS headers
      return {
        code = 204,
        {"Access-Control-Allow-Origin", "*"},
        {'Access-Control-Allow-Credentials', 'true'},
        {'Access-Control-Allow-Methods', 'GET, OPTIONS'},
        -- Custom headers and headers various browsers *should* be OK with but aren't
        {'Access-Control-Allow-Headers', 'DNT,Keep-Alive,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control'},
        -- Tell client that this pre-flight info is valid for 20 days
        {'Access-Control-Max-Age', 1728000},
        {'Content-Type', 'text/plain charset=UTF-8'},
        {'Content-Length', 0},
      }
    end

    if not (req.method == "GET" or req.method == "HEAD") then
      return nil, "Must be GET or HEAD"
    end

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
      local match = {req.path:match(routes[i])}
      if #match > 0 then
        for j = 1, #match do
          match[j] = unescape(match[j])
        end
        local success, err = pcall(function ()
          body, extra = routes[i + 1](unpack(match))
        end)
        if not success then body = {"error", err} end
        break
      end
    end

    if not body then
      return {code = 404}
    end
    local res = {
      code = 200,
      {"Date", date("!%a, %d %b %Y %H:%M:%S GMT")},
      {"Server", litVersion},
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

    -- Add CORS headers
    res[#res + 1] = {'Access-Control-Allow-Origin', '*'}
    res[#res + 1] = {'Access-Control-Allow-Methods', 'GET, OPTIONS'}
    res[#res + 1] = {'Access-Control-Allow-Headers', 'DNT,Keep-Alive,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control'}

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
