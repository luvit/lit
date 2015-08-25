
exports.name = "creationix/coro-net"
exports.version = "1.2.0"
exports.dependencies = {
  "creationix/coro-channel@1.2.0",
  "creationix/coro-fs@1.3.0",
}
exports.homepage = "https://github.com/luvit/lit/blob/master/deps/coro-net.lua"
exports.description = "An coro style client and server helper for tcp and pipes."
exports.tags = {"coro", "tcp", "pipe", "net"}
exports.license = "MIT"
exports.author = { name = "Tim Caswell" }

local uv = require('uv')
local wrapStream = require('coro-channel').wrapStream
local fs = require('coro-fs')
local env = require('env')
local isWindows = require('luvipath').isWindows

local function makeCallback(timeout)
  local thread = coroutine.running()
  local timer, done
  if timeout then
    timer = uv.new_timer()
    timer:start(timeout, 0, function ()
      if done then return end
      done = true
      timer:close()
      return assert(coroutine.resume(thread, nil, "timeout"))
    end)
  end
  return function (err, data)
    if done then return end
    done = true
    if timer then timer:close() end
    if err then
      return assert(coroutine.resume(thread, nil, err))
    end
    return assert(coroutine.resume(thread, data or true))
  end
end
exports.makeCallback = makeCallback

local function normalize(options)
  local t = type(options)
  if t == "string" then
    options = {path=options}
  elseif t == "number" then
    options = {port=options}
  elseif t ~= "table" then
    assert("Net options must be table, string, or number")
  end
  if options.port or options.host then
    return true,
      options.host or "127.0.0.1",
      assert(options.port, "options.port is required for tcp connections")
  elseif options.path then
    return false, options.path
  else
    error("Must set either options.path or options.port")
  end
end

local quotepattern = '(['..("%^$().[]*+-?"):gsub("(.)", "%%%1")..'])'
local function escape(str)
    return str:gsub(quotepattern, "%%%1")
end

local resolve
do
  local hosts
  local expires = 0
  local hostsPath = isWindows and
    env.get("SYSTEMROOT") .. "\\System32\\Drivers\\etc\\hosts" or
    "/etc/hosts"
  function resolve(host, port, options)
    options = options or {}
    local now = uv.now()
    if not hosts or now > expires then
      local err
      expires = now + 1000 * 60 * 5
      hosts, err = fs.readFile(hostsPath)
      if not hosts then return nil, err end
    end
    local list = {}
    local ipv4Pattern = "^%s*(%d+%.%d+%.%d+%.%d+)%s[^\n]*" .. escape(host)
    local ipv6Pattern = "^%s*([0-9a-fA-F][0-9a-fA-F:]+[0-9a-fA-F])%s[^\n]*" .. escape(host)

    if port then
      uv.getaddrinfo(nil, port, {socktype="stream"}, makeCallback(options.timeout))
      local result = coroutine.yield()
      port = result and result[1] and result[1].port
    end

    for line in hosts:gmatch("[^\n]+") do
      local addr = line:match(ipv4Pattern)
      if addr then
        list[#list + 1] = {
          addr = addr,
          family = "inet",
          port = port,
          source = hostsPath,
          socktype = options.socktype,
        }
      end
      addr = line:match(ipv6Pattern)
      if addr then
        list[#list + 1] = {
          addr = addr,
          family = "inet6",
          port = port,
          source = hostsPath,
          socktype = options.socktype,
        }
      end
    end
    if #list == 0 then
      assert(uv.getaddrinfo(host, port, options, makeCallback(options.timeout)))
      local result, err = coroutine.yield()
      if result then
        for i = 1, #result do
          list[#list + 1] = result[i]
        end
      end
      if #list == 0 then
        return nil, err
      end
    end
    return list
  end
end
exports.resolve = resolve

function exports.connect(options)
  local socket, success, err
  local isTcp, host, port = normalize(options)
  if isTcp then
    assert(uv.getaddrinfo(host, port, {
      socktype = options.socktype or "stream",
      family = options.family or "inet",
    }, makeCallback(options.timeout)))
    local res
    res, err = coroutine.yield()
    if not res then return nil, err end
    socket = uv.new_tcp()
    socket:connect(res[1].addr, res[1].port, makeCallback(options.timeout))
  else
    socket = uv.new_pipe(false)
    socket:connect(host, makeCallback(options.timeout))
  end
  success, err = coroutine.yield()
  if not success then return nil, err end
  local read, write = wrapStream(socket)
  return read, write, socket
end

function exports.createServer(options, onConnect)
  local server
  local isTcp, host, port = normalize(options)
  if isTcp then
    server = uv.new_tcp()
    assert(server:bind(host, port))
  else
    server = uv.new_pipe(false)
    assert(server:bind(host))
  end
  assert(server:listen(256, function (err)
    assert(not err, err)
    local socket = isTcp and uv.new_tcp() or uv.new_pipe(false)
    server:accept(socket)
    coroutine.wrap(function ()
      local success, failure = xpcall(function ()
        local read, write = wrapStream(socket)
        return onConnect(read, write, socket)
      end, debug.traceback)
      if not success then
        print(failure)
      end
      if not socket:is_closing() then
        socket:close()
      end
    end)()
  end))
  return server
end
