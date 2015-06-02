exports.name = "creationix/git-fs"
exports.version = "0.2.0-1"
exports.dependencies = {
  "creationix/git@1.0.1",
  "creationix/hex-bin@1.0.0",
}

--[[

Git Object Database
===================

Consumes a storage interface and return a git database interface

db.has(hash) -> bool                   - check if db has an object
db.load(hash) -> raw                   - load raw data, nil if not found
db.loadAny(hash) -> kind, value        - pre-decode data, error if not found
db.loadAs(kind, hash) -> value         - pre-decode and check type or error
db.save(raw) -> hash                   - save pre-encoded and framed data
db.saveAs(kind, value) -> hash         - encode, frame and save to objects/$ha/$sh
db.hashes() -> iter                    - Iterate over all hashes

db.getHead() -> hash                   - Read the hash via HEAD
db.getRef(ref) -> hash                 - Read hash of a ref
db.resolve(ref) -> hash                - Given a hash, tag, branch, or HEAD, return the hash
db.nodes(prefix) -> iter               - iterate over non-leaf refs
db.leaves(prefix) -> iter              - iterate over leaf refs
]]

local git = require('git')
local miniz = require('miniz')
local openssl = require('openssl')
local hexBin = require('hex-bin')
local uv = require('uv')

local numToType = {
  [1] = "commit",
  [2] = "tree",
  [3] = "blob",
  [4] = "tag",
  [6] = "ofs-delta",
  [7] = "ref-delta",
}

local encoders = git.encoders
local decoders = git.decoders
local frame = git.frame
local deframe = git.deframe
local deflate = miniz.deflate
local inflate = miniz.inflate
local digest = openssl.digest.digest
local binToHex = hexBin.binToHex
local hexToBin = hexBin.hexToBin

local band = bit.band
local bor = bit.bor
local lshift = bit.lshift
local rshift = bit.rshift
local byte = string.byte
local sub = string.sub
local match = string.format
local format = string.format
local concat = table.concat

local quotepattern = '(['..("%^$().[]*+-?"):gsub("(.)", "%%%1")..'])'
local function escape(str)
    return str:gsub(quotepattern, "%%%1")
end

local function applyDelta(base, delta) --> raw
  local deltaOffset = 0;

  -- Read a variable length number our of delta and move the offset.
  local function readLength()
    deltaOffset = deltaOffset + 1
    local b = byte(delta, deltaOffset)
    local length = band(b, 0x7f)
    local shift = 7
    while band(b, 0x80) > 0 do
      deltaOffset = deltaOffset + 1
      b = byte(delta, deltaOffset)
      length = bor(length, lshift(band(b, 0x7f), shift))
      shift = shift + 7
    end
    return length
  end

  assert(#base == readLength(), "base length mismatch")

  local outLength = readLength()
  local parts = {}
  while deltaOffset < #delta do
    deltaOffset = deltaOffset + 1
    local b = byte(delta, deltaOffset)

    if band(b, 0x80) > 0 then
      -- Copy command. Tells us offset in base and length to copy.
      local offset = 0
      local length = 0
      if band(b, 0x01) > 0 then
        deltaOffset = deltaOffset + 1
        offset = bor(offset, byte(delta, deltaOffset))
      end
      if band(b, 0x02) > 0 then
        deltaOffset = deltaOffset + 1
        offset = bor(offset, lshift(byte(delta, deltaOffset), 8))
      end
      if band(b, 0x04) > 0 then
        deltaOffset = deltaOffset + 1
        offset = bor(offset, lshift(byte(delta, deltaOffset), 16))
      end
      if band(b, 0x08) > 0 then
        deltaOffset = deltaOffset + 1
        offset = bor(offset, lshift(byte(delta, deltaOffset), 24))
      end
      if band(b, 0x10) > 0 then
        deltaOffset = deltaOffset + 1
        length = bor(length, byte(delta, deltaOffset))
      end
      if band(b, 0x20) > 0 then
        deltaOffset = deltaOffset + 1
        length = bor(length, lshift(byte(delta, deltaOffset), 8))
      end
      if band(b, 0x40) > 0 then
        deltaOffset = deltaOffset + 1
        length = bor(length, lshift(byte(delta, deltaOffset), 16))
      end
      if length == 0 then length = 0x10000 end
      -- copy the data
      parts[#parts + 1] = sub(base, offset + 1, offset + length)
    elseif b > 0 then
      -- Insert command, opcode byte is length itself
      parts[#parts + 1] = sub(delta, deltaOffset + 1, deltaOffset + b)
      deltaOffset = deltaOffset + byte
    else
      error("Invalid opcode in delta")
    end
  end
  local out = concat(parts)
  assert(#out == outLength, "final size mismatch in delta application")
  return concat(parts)
end

local function readUint32(buffer, offset)
  offset = offset or 0
  assert(#buffer >= offset + 4, "not enough buffer")
  return bor(
    lshift(byte(buffer, offset + 1), 24),
    lshift(byte(buffer, offset + 2), 16),
    lshift(byte(buffer, offset + 3), 8),
    byte(buffer, offset + 4)
  )
end

local function readUint64(buffer, offset)
  offset = offset or 0
  assert(#buffer >= offset + 8, "not enough buffer")
  return
    (lshift(byte(buffer, offset + 1), 24) +
    lshift(byte(buffer, offset + 2), 16) +
    lshift(byte(buffer, offset + 3), 8) +
    byte(buffer, offset + 4)) * 0x100000000 +
    lshift(byte(buffer, offset + 5), 24) +
    lshift(byte(buffer, offset + 6), 16) +
    lshift(byte(buffer, offset + 7), 8) +
    byte(buffer, offset + 8)
end

local function assertHash(hash)
  assert(hash and #hash == 40 and match(hash, "^%x+$"), "Invalid hash")
end

local function hashPath(hash)
  return format("objects/%s/%s", sub(hash, 1, 2), sub(hash, 3))
end

return function (storage)

  local db = { storage = storage }
  local fs = storage.fs

  -- Initialize the git file storage tree if it does't exist yet
  if not fs.access("HEAD") then
    assert(fs.mkdirp("objects"))
    assert(fs.mkdirp("refs/tags"))
    assert(fs.writeFile("HEAD", "ref: refs/heads/master\n"))
    assert(fs.writeFile("config", [[
[core]
  repositoryformatversion = 0
  filemode = true
  bare = true
[gc]
        auto = 0
]]))
  end

  local packs = {}
  local function makePack(packHash)
    local pack = packs[packHash]
    if pack then
      if pack.waiting then
        pack.waiting[#pack.waiting + 1] = coroutine.running()
        return coroutine.yield()
      end
      return pack
    end
    local waiting = {}
    pack = { waiting=waiting }

    local timer, indexFd, packFd, indexLength
    local hashOffset, crcOffset
    local offsets, lengths, packSize

    local function close()
      if pack then
        pack.waiting = nil
        if packs[packHash] == pack then
          packs[packHash] = nil
        end
        pack = nil
      end
      if timer then
        timer:stop()
        timer:close()
        timer = nil
      end
      if indexFd then
        fs.close(indexFd)
        indexFd = nil
      end
      if packFd then
        fs.close(packFd)
        packFd = nil
      end
    end

    local function timeout()
      coroutine.wrap(close)()
    end


    timer = uv.new_timer()
    uv.unref(timer)
    timer:start(2000, 2000, timeout)

    packFd = assert(fs.open("objects/pack/pack-" .. packHash .. ".pack"))
    local stat = assert(fs.fstat(packFd))
    packSize = stat.size
    assert(fs.read(packFd, 8, 0) == "PACK\0\0\0\2", "Only v2 pack files supported")

    indexFd = assert(fs.open("objects/pack/pack-" .. packHash .. ".idx"))
    assert(fs.read(indexFd, 8, 0) == '\255tOc\0\0\0\2', 'Only pack index v2 supported')
    indexLength = readUint32(assert(fs.read(indexFd, 4, 8 + 255 * 4)))
    hashOffset = 8 + 255 * 4 + 4
    crcOffset = hashOffset + 20 * indexLength
    local lengthOffset = crcOffset + 4 * indexLength
    local largeOffset = lengthOffset + 4 * indexLength
    offsets = {}
    lengths = {}
    local sorted = {}
    local data = assert(fs.read(indexFd, 4 * indexLength, lengthOffset))
    for i = 1, indexLength do
      local offset = readUint32(data, (i - 1) * 4)
      if band(offset, 0x80000000) > 0 then
        error("TODO: Implement large offsets properly")
        offset = largeOffset + band(offset, 0x7fffffff) * 8;
        offset = readUint64(assert(fs.read(indexFd, 8, offset)))
      end
      offsets[i] = offset
      sorted[i] = offset
    end
    table.sort(sorted)
    for i = 1, indexLength do
      local offset = offsets[i]
      local length
      for j = 1, indexLength - 1 do
        if sorted[j] == offset then
          length = sorted[j + 1] - offset
          break
        end
      end
      lengths[i] = length or (packSize - offset - 20)
    end

    local function loadHash(hash) --> offset

      -- Read first fan-out table to get index into offset table
      local prefix = hexToBin(hash:sub(1, 2)):byte(1)
      local first = prefix == 0 and 0 or readUint32(assert(fs.read(indexFd, 4, 8 + (prefix - 1) * 4)))
      local last = readUint32(assert(fs.read(indexFd, 4, 8 + prefix * 4)))

      for index = first, last do
        local start = hashOffset + index * 20
        local foundHash = binToHex(assert(fs.read(indexFd, 20, start)))
        if foundHash == hash then
          index = index + 1
          return offsets[index], lengths[index]
        end
      end
    end

    local function loadRaw(offset, length) -->raw
      -- Shouldn't need more than 32 bytes to read variable length header and
      -- optional hash or offset
      local chunk = assert(fs.read(packFd, 32, offset))
      local b = byte(chunk, 1)

      -- Parse out the git type
      local kind = numToType[band(rshift(b, 4), 0x7)]

      -- Parse out the uncompressed length
      local size = band(b, 0xf)
      local left = 4
      local i = 2
      while band(b, 0x80) > 0 do
        b = byte(chunk, i)
        i = i + 1
        size = bor(size, lshift(band(b, 0x7f), left))
        left = left + 7
      end

      -- Optionally parse out the hash or offset for deltas
      local ref
      if kind == "ref-delta" then
        ref = binToHex(chunk:sub(i + 1, i + 20))
        i = i + 20
      elseif kind == "ofs-delta" then
        b = byte(chunk, i)
        i = i + 1
        ref = band(b, 0x7f)
        while band(b, 0x80) > 0 do
          b = byte(chunk, i)
          i = i + 1
          ref = bor(lshift(ref + 1, 7), band(b, 0x7f))
        end
      end

      local compressed = assert(fs.read(packFd, length, offset + i - 1))
      local raw = inflate(compressed, 1)

      assert(#raw == size, "inflate error or size mismatch at offset " .. offset)

      if kind == "ref-delta" then
        error("TODO: handle ref-delta")
      elseif kind == "ofs-delta" then
        local base
        kind, base = loadRaw(offset - ref)
        raw = applyDelta(base, raw)
      end
      return kind, raw
    end

    function pack.load(hash) --> raw
      if not pack then
        return makePack(packHash).load(hash)
      end
      timer:again()
      local success, result = pcall(function ()
        local offset, length = loadHash(hash)
        if not offset then return end
        local kind, raw = loadRaw(offset, length)
        return frame(kind, raw)
      end)
      if success then return result end
      -- close()
      error(result)
    end

    packs[packHash] = pack
    pack.waiting = nil
    for i = 1, #waiting do
      assert(coroutine.resume(waiting[i], pack))
    end

    return pack
  end

  function db.has(hash)
    assertHash(hash)
    return storage.read(hashPath(hash)) and true or false
  end

  function db.load(hash)
    assert(hash, "hash required")
    hash = db.resolve(hash)
    assertHash(hash)
    local compressed, err = storage.read(hashPath(hash))
    if not compressed then
      for file in storage.leaves("objects/pack") do
        local packHash = file:match("^pack%-(%x+)%.idx$")
        if packHash then
          local raw
          raw, err = makePack(packHash).load(hash)
          if raw then return raw end
        end
      end
      return nil, err
    end
    return inflate(compressed, 1)
  end

  function db.loadAny(hash)
    local raw = assert(db.load(hash), "no such hash")
    local kind, value = deframe(raw)
    return kind, decoders[kind](value)
  end

  function db.loadAs(kind, hash)
    local actualKind, value = db.loadAny(hash)
    assert(kind == actualKind, "Kind mismatch")
    return value
  end

  function db.save(raw)
    local hash = digest("sha1", raw)
    -- 0x1000 = TDEFL_WRITE_ZLIB_HEADER
    -- 4095 = Huffman+LZ (slowest/best compression)
    storage.put(hashPath(hash), deflate(raw, 0x1000 + 4095))
    return hash
  end

  function db.saveAs(kind, value)
    if type(value) ~= "string" then
      value = encoders[kind](value)
    end
    return db.save(frame(kind, value))
  end

  function db.hashes()
    local groups = storage.nodes("objects")
    local prefix, iter
    return function ()
      while true do
        if prefix then
          local rest = iter()
          if rest then return prefix .. rest end
          prefix = nil
          iter = nil
        end
        prefix = groups()
        if not prefix then return end
        iter = storage.leaves("objects/" .. prefix)
      end
    end
  end

  function db.getHead()
    local head = storage.read("HEAD")
    if not head then return end
    local ref = head:match("^ref: *([^\n]+)")
    return ref and db.getRef(ref)
  end

  function db.getRef(ref)
    local hash = storage.read(ref)
    if hash then return hash:match("%x+") end
    local refs = storage.read("packed-refs")
    return refs and refs:match("(%x+) " .. escape(ref))
  end

  function db.resolve(ref)
    if ref == "HEAD" then return db.getHead() end
    local hash = ref:match("^%x+$")
    if hash and #hash == 40 then return hash end
    return db.getRef(ref)
        or db.getRef("refs/heads/" .. ref)
        or db.getRef("refs/tags/" .. ref)
  end

  local function makePackedIter(prefix, inner)
    local packed = storage.read("packed-refs")
    if not packed then return function () end end
    if prefix:byte(-1) ~= 47 then
      prefix = prefix .. "/"
    end
    if inner then
      return packed:gmatch(escape(prefix) .. "([^/ \r\n]+)/")
    else
      return packed:gmatch(escape(prefix) .. "([^/ \r\n]+)")
    end
  end

  local function commonIter(iter1, iter2)
    local seen = {}
    return function ()
      local item = iter1()
      if item then
        seen[item] = true
        return item
      end
      while true do
        item = iter2()
        if not item then return end
        if not seen[item] then
          seen[item] = true
          return item
        end
      end
    end
  end

  function db.nodes(prefix)
    return commonIter(
      storage.nodes(prefix),
      makePackedIter(prefix, true)
    )
  end

  function db.leaves(prefix)
    return commonIter(
      storage.leaves(prefix),
      makePackedIter(prefix, false)
    )
  end

  return db
end
