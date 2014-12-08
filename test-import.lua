local GitStorage = require("storage/fs")
local _, SophiaStorage = pcall(require, "storage/sophia")
local gitFrame = require('git').frame
local modes = require('git').modes
local uv = require('uv')
local pathJoin = require('luvi').path.join
local fs = require('fs')
local openssl = require('openssl')
local env = require('env')

local privateKey

local function test(storage)
  local function saveAs(type, body)
    return assert(storage:save(gitFrame(type, body)))
  end

  local author = {
    name = "Tim Caswell",
    email = "tim@creationix.com",
    date = { seconds = 1418058725, offset = 360 }
  }

  assert(storage:write("creationix/greetings/v0.0.1", saveAs("commit", {
    tree = saveAs("tree", {
      {
        name = "GREETINGS.txt",
        mode = modes.file,
        hash = saveAs("blob", "Hello World\n")
      }
    }),
    parents = {},
    committer = author,
    author = author,
    message = "Initial release of creationix/greetings v0.0.1\n",
    key = privateKey
  })))

end

coroutine.wrap(function ()
  print("Loading private key")
  local path = pathJoin(env.get("HOME"), ".ssh/id_rsa")
  local RSA_PRIVATE_KEY = assert(fs.readFile(path))
  privateKey = openssl.pkey.read(RSA_PRIVATE_KEY, true)
  print("Testing with git based backend")
  test(GitStorage:new(pathJoin(uv.cwd(), "db.git")))
  if SophiaStorage then
    print("Testing with sophia based backend")
    test(SophiaStorage:new(pathJoin(uv.cwd(), "db.sophia")))
  end
end)()
