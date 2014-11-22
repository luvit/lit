local git = require('./git')

local tree = {
  {
    name="git.lua",
    mode = git.modes.blob,
    hash = "29cd894c4841220e4458299f81cf0b50495497ea"
  },
  modules = {
    mode = git.modes.tree,
    hash = "4981015c9e6ef65409e9b88805f3ab59ef513d31"
  },
}

local tim = {
  name = "Tim Caswell",
  email = "tim@creationix.com",
  date = {
    seconds = 1416603902,
    offset = -360
  }
}

local commit = {
  tree = "e73f8e7021bdef8346ac79f4e2f9e2f90e656c24",
  parents = { },
  author = tim,
  committer = tim,
  message = "Start on lit system\n"
}

local hash, data = git.frame("commit", commit)

local expected = "781dafe7db0685aadfea89cc3656dfddec6db29f"
print("Expected: " .. expected)
print("Actual:   " .. hash)
p(data)
assert(hash == expected, "Hash mismatch!")

hash, data = git.frame("tree", tree)
expected = "e73f8e7021bdef8346ac79f4e2f9e2f90e656c24"
print("Expected: " .. expected)
print("Actual:   " .. hash)
p(data)
assert(hash == expected, "Hash mismatch!")

