local digest = require('openssl').digest.digest

local modes = {
  tree   = 16384, --  040000
  blob   = 33188, -- 0100644
  exec   = 33261, -- 0100755
  sym    = 40960, -- 0120000
  commit = 57344, -- 0160000
}
modes.file = modes.blob
exports.modes = modes

function modes.isBlob(mode)
  -- (mode & 0140000) == 0100000
  return bit.band(mode, 49152) == 32768
end

function modes.isFile(mode)
  -- (mode & 0160000) === 0100000
  return bit.band(mode, 57344) == 32768
end

function modes.toType(mode)
         -- 0160000
  return mode == 57344 and "commit"
         -- 040000
      or mode == 16384 and "tree"
         -- (mode & 0140000) == 0100000
      or bit.band(mode, 49152) == 32768 and "blob" or
         "unknown"
end



local encoders = {}
exports.encoders = encoders
local decoders = {}
exports.decoders = decoders


local function treeSort(a, b)
  return ((a.mode == modes.tree) and (a.name .. "/") or a.name)
       < ((b.mode == modes.tree) and (b.name .. "/") or b.name)
end

-- Given two hex characters, return a single character
local function hexToBin(cc)
  return string.char(tonumber(cc, 16))
end


-- Remove illegal characters in things like emails and names
local function safe(text)
  return text:gsub("^[%.,:;\"']+", "")
             :gsub("[%.,:;\"']+$", "")
             :gsub("[%z\n<>]+", "")
end

local function formatDate(date)
  local seconds = date.seconds
  local offset = date.offset
  assert(type(seconds) == "number", "date.seconds must be number")
  assert(type(offset) == "number", "date.offset must be number")
  return string.format("%d %+03d%02d", seconds, offset / 60, offset % 60)
end

local function formatPerson(person)
  assert(type(person.name) == "string", "person.name must be string")
  assert(type(person.email) == "string", "person.email must be string")
  assert(type(person.date) == "table", "person.date must be table")
  return safe(person.name) ..
    " <" .. safe(person.email) .. "> " ..
    formatDate(person.date)
end

function encoders.blob(blob)
  assert(type(blob) == "string", "blobs must be strings")
  return blob
end

function encoders.tree(tree)
  assert(type(tree) == "table", "trees must be tables")
  local parts = {}
  for key, value in pairs(tree) do
    local name = value.name or key
    assert(type(name) == "string", "tree entries must have string name or key")
    assert(type(value.mode) == "number", "tree entry mode must be number")
    assert(type(value.hash) == "string", "tree entry hash must be string")
    parts[#parts + 1] = {
      name = name,
      mode = value.mode,
      hash = value.hash,
    }
  end
  table.sort(parts, treeSort)
  for i = 1, #parts do
    local entry = parts[i]
    parts[i] = string.format("%o %s\0%s",
      entry.mode,
      entry.name,
      string.gsub(entry.hash, "..", hexToBin))
  end
  return table.concat(parts)
end

function encoders.tag(tag)
  assert(type(tag) == "table", "annotated tags must be tables")
  assert(type(tag.object) == "string", "tag.object must be hash string")
  assert(type(tag.type) == "string", "tag.type must be string")
  assert(type(tag.tag) == "string", "tag.tag must be string")
  assert(type(tag.tagger) == "table", "tag.tagger must be table")
  assert(type(tag.message) == "string", "tag.message must be string")
  return string.format(
    "object %s\ntype %s\ntag %s\ntagger %s\n\n%s",
    tag.object, tag.type, tag.tag, formatPerson(tag.tagger), tag.message)
end

function encoders.commit(commit)
  assert(type(commit) == "table", "commits must be tables")
  assert(type(commit.tree) == "string", "commit.tree must be hash string")
  assert(type(commit.parents) == "table", "commit.parents must be table")
  assert(type(commit.author) == "table", "commit.author must be table")
  assert(type(commit.committer) == "table", "commit.committer must be table")
  assert(type(commit.message) == "string", "commit.message must be string")
  local parents = {}
  for i = 1, #commit.parents do
    local parent = commit.parents[i]
    assert(type(parent) == "string", "commit.parents must be hash strings")
    parents[i] = string.format("parent %s\n", parent)
  end
  return string.format(
    "tree %s\n%sauthor %s\ncommitter %s\n\n%s",
    commit.tree, table.concat(parents), formatPerson(commit.author),
    formatPerson(commit.committer), commit.message)
end

function exports.frame(name, body)
  assert(type(name) == "string", "type must be a string")
  assert(body, "missing body")
  if type(body) ~= "string" then
    local encoder = encoders[name]
    assert(encoder, "Unknown type: " .. name)
    body = encoder(body)
  end
  body = string.format("%s %d\0", name, #body) .. body
  return digest("sha1", body), body
end
