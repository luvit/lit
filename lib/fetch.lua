local git = require('creationix/git')

return function (storage, upstream, initialHash)
  local queue = {initialHash}
  local data
  repeat
    local hash = table.remove(queue)
    local kind, raw, err
    raw, err = upstream.load(hash)
    if not raw then
      if not data and not err then return end
      return nil, err or "Missing sub objects in upstream"
    end
    if not data then data = raw end
    local body
    kind, body = git.deframe(raw)
    print("Fetching " .. kind .. ' ' .. hash)
    if kind == 'tree' then
      local tree = git.decoders.tree(body)
      for i = 1, #tree do
        local subHash = tree[i].hash
        if not storage.has(subHash) then
          queue[#queue + 1] = subHash
        end
      end
    elseif kind == "tag" then
      local tag = git.decoders.tag(body)
      -- TODO: verify signature
      storage.write(tag.tag, hash)
      local subHash = tag.object
      if not storage.has(subHash) then
        queue[#queue + 1] = subHash
      end
    elseif kind ~= "blob" then
      error("Unsupported type")
    end
    assert(storage.save(raw) == hash)
  until #queue == 0
  return data
end
