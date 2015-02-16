return function(db, url)
  local uv = require('uv')
  local semver = require('semver')
  local makeUpstream = require('./upstream')
  local git = require('git')
  local deframe = git.deframe
  local decoders = git.decoders

  -- Implement very basic connection keepalive using an uv_idle timer
  -- This will disconnect very quickly if a connect() isn't called
  -- soon after a disconnect()
  local idler = uv.new_idle()
  local upstream, up
  local function connect()
    if up then return end
    up = true
    uv.idle_stop(idler)
    upstream = upstream or makeUpstream(db, url)
  end
  local function close()
    uv.idle_stop(idler)
    if upstream then
      upstream.close()
      upstream = nil
    end
  end
  local function disconnect()
    if not up then return end
    up = false
    uv.idle_start(idler, close)
  end

  local rawMatch = db.match
  function db.match(author, tag, version)
    local match, hash = rawMatch(author, tag, version)
    connect()
    local upMatch, upHash = upstream.match(author .. '/' .. tag, version)
    disconnect()
    if semver.gte(match, upMatch) then
      return match, hash
    end
    return upMatch, upHash
  end

  local rawLoad = db.load
  function db.load(hash)
    local kind, value = rawLoad(hash)
    if kind then return kind, value end
    connect()
    local raw, err = upstream.load(hash)
    disconnect()
    if not raw then
      return nil, value or err or "no such hash"
    end
    kind, value = deframe(raw)
    assert(db.save(kind, value) == hash, "hash mismatch")
    return kind, decoders[kind](value)
  end


  return db
end
