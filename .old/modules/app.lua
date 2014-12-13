local db = require('./git-fs')("test.git")
local git = require('./git')
local modes = git.modes


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

