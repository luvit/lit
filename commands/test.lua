local modes = require('creationix/git').modes

local makeDb = require('../lib/db')
local makeStorage = require('../lib/storage-git')
local makeUpstream = require('../lib/up-storage')

local function generateData(db, config)
  for major = 0, 1 do
    for minor = 0, 1 do
      for patch = 0, 1 do
        local hash = db.saveAs("tree", {
          { name = "GREETINGS.txt",
            mode = modes.file,
            hash = db.saveAs("blob", "Hello World\n") },
          { name = "README.md",
            mode = modes.file,
            hash = db.saveAs("blob", "#My project\n\nThis is a sample project\n") },
          { name = "package.lua",
            mode = modes.file,
            hash = db.saveAs("blob", 'return { version = "' .. major .. '.' .. minor .. '.' .. patch .. '", name = "creationix/greeting" }\n') },
        })
        local tag, tagHash = db.tag(config, hash, "Test publish")
        p(tag, tagHash)
      end
    end
  end
end

local function readTest(db, version)
  local match, hash = db.match("creationix/greeting", version)
  print(version, match, hash, version and db.read("creationix/greeting", version))
end

local function readAllTest(db)
  for major = 0, 1 do
    readTest(db, tostring(major))
    for minor = 0, 1 do
      readTest(db, major .. '.' .. minor)
      for patch = 0, 1 do
        readTest(db, major .. '.' .. minor .. '.' .. patch)
      end
    end
  end
  readTest(db)
  readTest(db, "2")
end

local function importTest(db, version)
  print("import", version)
  local hash = db.read("creationix/greeting", version)
  local tag = db.loadAs("tag", hash)
  p(tag.tag)
end

local function importAllTest(db)
  for major = 0, 1 do
    for minor = 0, 1 do
      for patch = 0, 1 do
        importTest(db, major .. '.' .. minor .. '.' .. patch)
      end
    end
  end
end

local upstream = makeUpstream(makeStorage("test.upstream.git"))
local storage = makeStorage("test.local.git")
local remote = makeUpstream(makeStorage("test.remote.git"))

local udb = makeDb(upstream)
local ldb = makeDb(storage, upstream)
local rdb = makeDb(storage, remote)

print("\nGenerate data at remote")
generateData(udb, require('../lib/config'))
print("\nRead tests at remote (local read tests)")
readAllTest(udb)
print("\nRead tests at local (remote read tests)")
readAllTest(ldb)
print("\nImport from remote to local")
importAllTest(ldb)
print("\nRead tests at local (local read tests)")
readAllTest(ldb)
print("\nImport Again")
importAllTest(ldb)

print("\nPush tests")
for major = 0, 1 do
  for minor = 0, 1 do
    for patch = 0, 1 do
      local version = major .. '.' .. minor .. '.' .. patch
      local name = "creationix/greeting"
      print("push", name, version)
      assert(rdb.push(name, version))
    end
  end
end
