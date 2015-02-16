--[[

Core Functions
==============

These are the high-level actions.  This consumes a database instance

core.add(path) -> author, tag, version, hash - Import a package complete with signed tag.
]]

-- Takes a time struct with a date and time in UTC and converts it into
-- seconds since Unix epoch (0:00 1 Jan 1970 UTC).
-- Trickier than you'd think because os.time assumes the struct is in local time.
local function now()
  local t_secs = os.time() -- get seconds if t was in local time.
  local t = os.date("*t", t_secs) -- find out if daylight savings was applied.
  local t_UTC = os.date("!*t", t_secs) -- find out what UTC t was converted to.
  t_UTC.isdst = t.isdst -- apply DST to this time if necessary.
  local UTC_secs = os.time(t_UTC) -- find out the converted time in seconds.
  return {
    seconds = t_secs,
    offset = os.difftime(t_secs, UTC_secs) / 60
  }
end

local log = require('./log')

return function (db, config, getKey)

  local pkg = require('./pkg')
  local sshRsa = require('ssh-rsa')
  local git = require('git')
  local encoders = git.encoders

  local core = {}

  function core.add(path)
    local author, tag, version = pkg.normalize(pkg.query(path))
    local kind, hash = db.import(path)
    local oldTagHash = db.read(author, tag, version)
    local fullTag = author .. "/" .. tag .. '/v' .. version
    if oldTagHash then
      local old = db.loadAs("tag", oldTagHash)
      if old.type == kind and old.object == hash then
        -- This package is already imported and tagged
        log("no change", fullTag)
        return author, tag, version, oldTagHash
      end
      log("replacing tag with new contents", fullTag, "failure")
    end
    local encoded = encoders.tag({
      object = hash,
      type = kind,
      tag = author .. '/' .. tag .. "/v" .. version,
      tagger = {
        name = config.name,
        email = config.email,
        date = now()
      },
      message = ""
    })
    local key = getKey()
    if key then
      encoded = sshRsa.sign(encoded, key)
    end
    local tagHash = db.save("tag", encoded)
    db.write(author, tag, version, tagHash)
    log("new tag", fullTag, "success")
    return author, tag, version, tagHash
  end

  return core
end
