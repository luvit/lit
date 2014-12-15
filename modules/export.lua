local log = require('lit-log')
local makeChroot = require('coro-fs').chroot
local gitDeframe = require('git').deframe
local decodeTag = require('git').decoders.tag
local modes = require('git').modes
local verify = require('verify')
local pathJoin = require('luvi').path.join

return function (config, storage, base, tag)
  local fs = makeChroot(base)

  local function loadAs(typ, hash)
    local value, actualType = gitDeframe(assert(storage:load(hash)))
    assert(typ == actualType, "type mistmatch")
    return value
  end

  local function exportBlob(path, hash)
    log("export blob", path)
    return assert(fs.writeFile(path, loadAs("blob", hash)))
  end

  local function exportLink(path, hash)
    log("export link", path)
    return assert(fs.symlink(path, loadAs("blob", hash)))
  end

  local function exportTree(path, hash)
    log("export tree", path)
    fs.mkdirp(path)
    local items = loadAs("tree", hash)
    for i = 1, #items do
      local item = items[i]
      local exporter = modes.isFile(item.mode) and exportBlob
                    or item.mode == modes.sym and exportLink
                    or item.mode == modes.tree and exportTree
                    or nil
      exporter(pathJoin(path, item.name), item.hash)
    end
  end

  local hash = assert(storage:read(tag))
  log("tag hash", hash)
  local raw = assert(storage:load(hash))
  local typ
  raw, typ = gitDeframe(raw, true)
  assert(typ == "tag")
  local signature
  raw, signature = string.match(raw, "^(.*)(%-%-%-%-%-BEGIN RSA SIGNATURE%-%-%-%-%-.*)$")
  -- TODO: get public key and verify
  -- local publicKey = string.match(tag, "^[^/]+")
  -- verify(raw, signature, publicKey)
  local tagData = decodeTag(raw)
  assert(tagData.tag == tag)
  tagData.signature = signature

  if tagData.type == "tree" then
    exportTree(".", tagData.object)
  else
    exportBlob(".", tagData.object)
  end

end
