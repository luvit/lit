return function ()

  local waiters = {}
  local function waitFor(name)
    local thread = coroutine.running()
    local list = waiters[name]
    if list then
      list[#list + 1] = thread
    else
      waiters[name] = {thread}
    end
    return coroutine.yield()
  end

  local function emit(name, value)
    local list = waiters[name]
    if not list then return end
    waiters[name] = nil
    for i = 1, #list do
      assert(coroutine.resume(list[i], value))
    end
  end

  local function fail(err)
    local events = waiters
    waiters = {}
    for _, list in pairs(events) do
      for i = 1, #list do
        assert(coroutine.resume(list[i], nil, err))
      end
    end
  end

  return waitFor, emit, fail
end
