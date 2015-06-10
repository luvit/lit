--[[

Copyright 2014-2015 The Luvit Authors. All Rights Reserved.

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
GET /packages/$AUTHOR/$TAG/$VERSION.zip -> zip bundle of app and dependencies

GET /search/$query -> list of matches

]]

local pathJoin = require('luvi').path.join
local digest = require('openssl').digest.digest
local date = require('os').date
local jsonStringify = require('json').stringify
local jsonParse = require('json').parse
local modes = require('git').modes
local exportZip = require('export-zip')
local calculateDeps = require('calculate-deps')
local queryDb = require('pkg').queryDb
local installDeps = require('install-deps').toDb

local litVersion = "Lit " .. require('../package').version

local function hex_to_char(x)
  return string.char(tonumber(x, 16))
end

local function unescape(url)
  return url:gsub("%%(%x%x)", hex_to_char)
end

local function found(terms, data)
  if not (terms and data) then return 0 end
  local count = 0
  if type(data) == "table" then
    for i = 1, #data do
      count = count + found(terms, data[i])
    end
  else
    for i = 1, #terms do
      local term = terms[i]
      if data:match(term) then
        count = count + 1
      end
    end
  end
  return count
end

local quotepattern = '(['..("%^$().[]*+-?"):gsub("(.)", "%%%1")..'])'
local function escape(str)
    return str:gsub(quotepattern, "%%%1")
end

local function compileGlob(glob)
  local parts = {}
  for a, b in glob:gmatch("([^*]*)(%**)") do
    if #a > 0 then
      parts[#parts + 1] = escape(a)
    end
    if #b > 0 then
      parts[#parts + 1] = ".*"
    end
  end
  return table.concat(parts)
end

local metaCache = {}

return function (db, prefix)

  local function makeUrl(kind, hash, filename)
    return prefix .. "/" .. kind .. "s/" .. hash .. '/' .. filename
  end

  local function loadMeta(author, name, version)
    local hash
    if not version then
      version, hash = (db.offlineMatch or db.match)(author, name)
    else
      hash = db.read(author, name, version)
    end
    if not hash then
      error("No such version " .. author .. "/" .. name .. "@" .. version)
    end
    local cached = metaCache[hash]
    if cached then return cached end
    local tag = db.loadAs("tag", hash)
    local meta = tag.message:match("%b{}")
    meta = meta and jsonParse(meta) or {}
    meta.url = prefix .. "/packages/" .. author .. "/" .. name .. "/v" .. version
    meta.version = version
    meta.hash = hash
    meta.tagger = tag.tagger
    meta.type = tag.type
    meta.object = tag.object
    metaCache[hash] = meta
    return meta
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
        names = prefix .. "/packages/{author}",
        versions = prefix .. "/packages/{author}/{name}",
        package = prefix .. "/packages/{author}/{name}/{version}",
        search = prefix .. "/search/{query}",
      }
    end,
    "^/packages/([^/]+)/(.+)/v([^/]+)%.zip$", function (author, name, version)

      local meta, kind, hash = queryDb(db, db.read(author, name, version))

      if kind ~= "tree" then
        error("Can only create zips from trees")
      end

      local deps = {}
      calculateDeps(db, deps, meta.dependencies)
      hash = installDeps(db, hash, deps)

      local zip = exportZip(db, hash)
      local filename = meta.name:match("[^/]+$") .. "-v" .. meta.version .. ".zip"

      return zip, {
        {"Content-Type", "application/zip"},
        {"Content-Disposition", "attachment; filename=" .. filename}
      }
    end,
    "^/packages/([^/]+)/(.+)/v([^/]+)$", function (author, name, version)
      local meta = loadMeta(author, name, version)
      meta.score = nil
      local filename = author .. "/" .. name .. "-v" .. version
      if meta.type == "blob" then
        filename = filename .. ".lua"
      end
      meta.url = makeUrl(meta.type, meta.object, filename)
      return meta
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
    "^/search/(.*)$", function (raw)
      local query = { raw = raw }
      local keys = {"author", "tag", "name", "depends"}
      for i = 1, #keys do
        local key = keys[i]
        local terms = {}
        local function replace(match)
          match = compileGlob(match)
          if key == "depends" then
            match = "^" .. match .. "%f[@]"
          else
            match = "^" .. match .. "$"
          end
          terms[#terms + 1] = match
          return ''
        end
        raw = raw:gsub(key .. " *[:=] *([^ ]+) *", replace)
        raw = raw:gsub(key .. ' *[:=] *"([^"]+)" *', replace)
        if #terms > 0 then
          query[key] = terms
        end
      end
      do
        local terms = {}
        local function replace(match)
          terms[#terms + 1] = compileGlob(match, false)
          return ''
        end
        raw = raw:gsub('"([^"]+)" *', replace)
        raw = raw:gsub("([^ ]+) *", replace)
        assert(#raw == 0, "unable to parse query string")
        if #terms > 0 then
          query.search = terms
        end
      end

      local matches = {}
      for author in db.authors() do
        -- If an authors filter is given, restrict to given authors
        -- Otherwise, allow all authors.

        local skip, s1
        if query.author then
          s1 = found(query.author, author)
          skip = s1 == 0
        else
          s1 = 0
          skip = false
        end

        if not skip then
          for name in db.names(author) do
            skip = false
            local s2, s3, s4, s5
            if query.name then
              s2 = found(query.name, name)
              skip = s2 == 0
            else
              s2 = 0
            end
            local meta
            if not skip then
              meta = loadMeta(author, name)
              if meta.obsolete then
                skip = true
              end
            end
            if not skip then
              if query.tag then
                s3 = found(query.tag, meta.tags) +
                     found(query.tag, meta.keywords)
                skip = s3 == 0
              else
                s3 = 0
              end
            end
            if not skip and query.depends then
              s4 = found(query.depends, meta.dependencies)
              skip = s4 == 0
            else
              s4 = 0
            end
            if not skip and query.search then
              s5 =
                found(query.search, name) +
                found(query.search, meta.description) +
                found(query.search, meta.tags) +
                found(query.search, meta.keywords)
              skip = s5 == 0
            else
              s5 = 0
            end

            if not skip then
              meta.score = s1 + s2 + s3 + s4 + s5
              matches[author .. "/" .. name] = meta
            end
          end
        end
      end
      local res = {
        query = query,
        matches = matches,
        upstream = db.upstream,
      }
      return res
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


    local path = pathJoin(req.path)
    local headers = {}
    for i = 1, #req do
      local key, value = unpack(req[i])
      headers[key:lower()] = value
    end
    if not prefix then
      local host = headers.host
      prefix = host and "http://" .. host or ""
    end
    local body, extra
    for i = 1, #routes, 2 do
      local match = {path:match(routes[i])}
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
