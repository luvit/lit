local tcp = require('coro-tcp')
local httpCodec = require('http-codec')
local websocketCodec = require('websocket-codec')

local log = require('../lib/log')
local wrapper = require('../lib/wrapper')
local readWrap, writeWrap = wrapper.reader, wrapper.writer
local makeRemote = require('../lib/codec').makeRemote
local handlers = require('../lib/handlers')

local db = require('../lib/config').db
local storage = db.storage
local pathJoin = require('luvi').path.join
local digest = require('openssl').digest.digest
local git = require('git')
local date = require('os').date
local jsonStringify = require('json').stringify

local function loadContents(parts, root, parent, name, hash)
  local kind, raw = git.deframe(db.load(hash))
  local data = git.decoders[kind](raw)
  local path
  local size = #data
  local filename
  if kind == "blob" then
    if parent then
      path = parent .. "/" .. name
    else
      path = name .. ".lua"
    end
    filename = path:match("[^/]+$")
  elseif kind == "tree" then
    if parent then
      path = parent .. '/' .. name .. '/'
    else
      path = name .. '/'
    end
    filename = name
  end
  parts[#parts + 1] = '  <tr>'

  local link = string.format('/%s?name=%s', hash, filename)
  parts[#parts + 1] = string.format('    <td><a href="%s">%s</a></td>', link, hash)
  parts[#parts + 1] = string.format('    <td>%s</td>', size)
  parts[#parts + 1] = string.format('    <td>%s</td>', path)
  parts[#parts + 1] = '  </tr>'
  if kind == "tree" then
    local newParent = parent and parent .. '/' .. name or name
    for i = 1, #data do
      local entry = data[i]
      loadContents(parts, root, newParent, entry.name, entry.hash)
    end
  end
end

local function handleRequest(req)
  local path = pathJoin(req.path)
  local hash, filename = req.path:match("^/([0-9a-f]+)%?name=(.*)$")
  local etag, res
  if hash then
    local kind, raw = git.deframe(storage.load(hash))
    local data = git.decoders[kind](raw)
    etag = '"' .. hash .. '"'
    if kind == "blob" then
      res = {
        code = 200,
        body = data,
        {"Content-Disposition", "attachment; filename=" .. filename},
        {"Content-Length", #data},
      }
    else
      local body = jsonStringify(data) .. "\n"
      res = {
        code = 200,
        body = body,
        {"Content-Disposition", "attachment; filename=" .. filename .. ".json"},
        {"Content-Type", "application/json"},
        {"Content-Length", #body},
      }
    end
  else
    local parts = {
      '<!doctype html>',
      '<head>',
      '  <meta charset="utf-8">',
      '',
      '</head>',
    }
    local title = path
    local iter = storage.dir(path)
    if iter then
      parts[#parts + 1] = "<ul>"
      for entry in iter do
        local newPath = pathJoin(path, entry.name)
        if entry.type == "directory" or entry.name:match("^v") then
          parts[#parts + 1] = string.format('  <li><a href="%s">%s</a></li>',  newPath, entry.name)
        end
      end
      parts[#parts + 1] = "</ul>"
    else
      parts[#parts + 1] = "<dl>"
      local name, version, sub = string.match(path, "/(.*)/v([^/]*)(.*)")
      local tagHash = db.read(name, version)
      local tag = db.loadAs("tag", tagHash)
      local meta = {
        "Name",  name,
        "Version", version,
        "Hash", tagHash,
        "Object", tag.object,
        "Author", string.format("%s &lt;%s&gt;", tag.tagger.name, tag.tagger.email),
      }
      local newest = db.match(name, version)
      if newest ~= version then
        local newestPath = pathJoin(path, "..", "v" .. newest)
        meta[#meta + 1] = "Newer Version"
        meta[#meta + 1] = string.format('<a href="%s">%s</a>', newestPath, newest)
      end

      if #sub == 0 then
        for i = 1, #meta, 2 do
          parts[#parts + 1] = string.format('  <dt>%s:</dt><dd>%s</dd>', meta[i], meta[i + 1])
        end
        parts[#parts + 1] = '  <dt>Contents:</dt><dd>'
        local base = name:match("[^/]+$")
        parts[#parts + 1] = '  <table>'
        parts[#parts + 1] = '  <tr><th>Hash</th><th>Size</th><th>Path</th></tr>'
        loadContents(parts, path, nil, base, tag.object)
        parts[#parts + 1] = '  </table>'
        parts[#parts + 1] = '  </dd>'
        parts[#parts + 1] = "</dl>"
      else
      end
    end
    parts[4] = '  <title>' .. title .. '</title>'
    local body = table.concat(parts, "\n") .. "\n"
    etag = string.format('"%s"', digest("sha1", body))
    res = {
      code = 200,
      body = body,
      {"Content-Length", #body},
      {"Content-Type", "text/html"},
    }
  end

  res[#res + 1] = {"Date", date("!%a, %d %b %Y %H:%M:%S GMT")}
  res[#res + 1] = {"Server", "lit"}

  if etag then
    res[#res + 1] = {"Etag", etag}

    local headers = {}
    for i = 1, #req do
      local pair = req[i]
      headers[pair[1]:lower()] = pair[2]
    end
    local oldEtag = headers['if-none-match']
    if etag == oldEtag then
      res.code = 304
      res.body = ""
    end
  end


  if req.method == "HEAD" then
    res.body = ""
  end

  return res
end

tcp.createServer("127.0.0.1", 4822, function (rawRead, rawWrite, socket)

  -- Handle the websocket handshake at the HTTP level
  local read, updateDecoder = readWrap(rawRead, httpCodec.decoder())
  local write, updateEncoder = writeWrap(rawWrite, httpCodec.encoder())

  local function upgrade(res)
    write(res)

    -- Upgrade the protocol to websocket
    updateDecoder(websocketCodec.decode)
    updateEncoder(websocketCodec.encode)

    -- Log the client connection
    local peerName = socket:getpeername()
    peerName = peerName.ip .. ':' .. peerName.port
    log("client connected", peerName)

    -- Proces the client using server handles
    local remote = makeRemote(read, write)
    local success, err = xpcall(function ()
      for command, data in remote.read do
        log("client command", peerName .. " - " .. command)
        local handler = handlers[command]
        if handler then
          handler(remote, data)
        else
          remote.writeAs("error", "no such command " .. command)
        end
      end
    end, debug.traceback)
    if not success then
      log("client error", err, "err")
      remote.writeAs("error", string.match(err, ":%d+: *([^\n]*)"))
      remote.close()
    end
    log("client disconnected", peerName)
  end

  for req in read do
    local res, err = websocketCodec.handleHandshake(req, "lit")
    if res then return upgrade(res) end
    local body = {}
    for chunk in read do
      if #chunk > 0 then
        body[#body + 1] = chunk
      else
        break
      end
    end
    body = table.concat(body)
    if req.method == "GET" or req.method == "HEAD" then
      req.body = #body > 0 and body or nil
      res, err = handleRequest(req)
    end
    if err then
      write({code=400})
      write(err or "lit websocket request required")
      return write()
    end
    write(res)
    write(res.body)
  end

end)

-- Never return so that the command keeps running.
coroutine.yield()
