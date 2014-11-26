local db = require('./git-fs')("test.git")
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
  db:init()
  local commitHash = db:save({
    tree = db:save({
      { name = "greetings.txt",
        mode = modes.file,
        hash = db:save("Hello World\n", "blob")
      },
      { name = "stuff",
        mode = modes.exec,
        hash = db:save(string.rep("12345", 1042), "blob")
      }
    }, "tree"),
    parents = {},
    author = tim,
    committer = tim,
    message = "Test Commit\n"
  }, "commit")
  db:writeRef("refs/heads/master", commitHash)
  db:setHead("refs/heads/master")

  local commit, tree, kind
  commit, kind = db:load("HEAD")
  assert(kind == "commit")
  p(commit)
  tree, kind = db:load(commit.tree)
  assert(kind == "tree")
  p(kind, tree)
  for i = 1, #tree do
    local entry
    entry, kind = db:load(tree[i].hash)
    p(tree[i], kind, entry)
  end
end)()

