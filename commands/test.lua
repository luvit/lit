local modes = require('creationix/git').modes

local makeDb = require('../lib/db')
local makeStorage = require('../lib/storage-git')

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

local function readTests(db)
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

local function pushTests(db)
  for major = 0, 1 do
    for minor = 0, 1 do
      for patch = 0, 1 do
        local version = major .. '.' .. minor .. '.' .. patch
        print("push", version)
        assert(db.push("creationix/greeting", version))
      end
    end
  end
end

local function importTests(db)
  for major = 0, 1 do
    for minor = 0, 1 do
      for patch = 0, 1 do
        local version = major .. '.' .. minor .. '.' .. patch
        print("import", version)
        local hash = db.read("creationix/greeting", version)
        local tag = db.loadAs("tag", hash)
        p(tag.tag)
      end
    end
  end
end

local storage = makeStorage("test.local.git")
print("Offline population")
local db = makeDb(storage)
print("\nGenerate data at local")
generateData(db, require('../lib/config'))
-- print("\nRead tests at (local read tests)")
-- readTests(db)

db = makeDb(storage, "localhost")
print("\npushing modules to upstream")
pushTests(db)
print("\nRead tests at (local read tests with remote backup)")
readTests(db)

-- storage = makeStorage("test.new.git")
-- db = makeDb(storage, "localhost")
-- print("\nRead tests with empty local (remote read)")
-- readTests(db)

