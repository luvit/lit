local waiters = {}
local function waitFor(name)
  local thread = coroutine.running()
  local list = waiters[name]
  if list then
    list[#list + 1] = thread
  else
    list = {thread}
    waiters[name] = list
  end
  return coroutine.yield()
end

local function emit(name, value)
  local list = waiters[name]
  if not list then return end
  waiters[name] = nil
  for i = 1, #list do
    list[i](value)
  end
end

local function fail(err)
  local events = waiters
  waiters = {}
  for _, list in pairs(events) do
    for i = 1, #list do
      list[i](nil, err)
    end
  end
end


function upstream.pull(name, version)
  local ref = name .. '/v' .. version
  write("query", "PULL " .. ref)
  return waitFor(ref)
end

function upstream.push(hash)
  local data = storage.load(hash)
  local kind, body = git.deframe(data)
  assert(kind == 'tag')
  write("send", data)
  local tag = git.decoders.tag(body)
  return waitFor(hash)
end
