local log = require('lit-log')
local makeChroot = require('coro-fs').chroot
local gitFrame = require('git').frame
local modes = require('git').modes
local pkey = require('openssl').pkey
local sign = require('sign')


return function (config, storage, base, tag, message)
  local fs = makeChroot(base)

  local function saveAs(type, body)
    return assert(storage:save(gitFrame(type, body)))
  end

  local function importTree(path)
    log("import tree", path)
    fs.scandir(path, function (entry)
      p(entry)
    end)
    return "XXXX"
  end

  local function importBlob(path)
    log("import blob", path)
    return saveAs("blob", fs.readFile(path))
  end

  local stat = fs.stat('.')
  local hash, typ
  log("import", base)
  if stat.type == "directory" then
    hash = importTree('.')
    typ = "tree"
  elseif stat.type == "file" then
    hash = importBlob('.')
    typ = "blob"
  end

  local keyData = assert(fs.readFile(config["private key"]))
  local key = pkey.read(keyData, true)

  local raw = gitFrame("tag", {
    object = hash,
    type = typ,
    tag = tag,
    tagger = {
      name = config.name,
      email = config.email,
      date = {}
    },
    message = message
  })

  raw = sign(raw, key)

  hash = storage:save(raw)
  storage:write(tag, hash)
  return tag, hash
end
