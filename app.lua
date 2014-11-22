local db = require('./git-fs')
local git = require('./git')
local modes = git.modes

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

coroutine.wrap(function ()
  local tim = {
    name = "Tim Caswell",
    email = "tim@creationix.com",
    date = now(),
  }
  db.init()
  local commitHash = db.save("commit", {
    tree = db.save("tree", {
      { name = "greetings.txt",
        mode = modes.file,
        hash = db.save("blob", "Hello World\n")
      }
    }),
    parents = {},
    author = tim,
    committer = tim,
    message = "Test Commit\n"
  })
  db.writeRef("refs/heads/master", commitHash)
  db.setHead("refs/heads/master")
end)()

