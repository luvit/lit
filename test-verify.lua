local JSON = require('json')
local GitStorage = require("storage/fs")
local fs = require('fs')
local uv = require('uv')
local pathJoin = require('luvi').path.join
local git = require('git')

local db

local function loadAs(typ, hash)
  local raw, err, t, body
  body, err = db:load(hash)
  p(body, err)
  if not body then return nil, err end
  raw, t = git.deframe(body, true)
  local s = string.find(raw, "-----BEGIN RSA SIGNATURE-----")
  if s then
    local sig = string.sub(raw, s)
    raw = string.sub(raw, 1, s - 1)
    p(raw, sig)
  end
  body = git.deframe(body)
  assert(t == typ)
  return body
end

local function verify(owner, commit)
  local json = assert(fs.readFile("keys/" .. owner .. ".json"))
  local data = JSON.parse(json)
  p(data)
  p{
    owner = owner,
    commit = commit
  }
end

coroutine.wrap(function ()
  db = GitStorage:new(pathJoin(uv.cwd(), "db.git"))
  local hash = db:read("creationix/greetings/v0.0.1")
  local commit = loadAs("commit", hash)
  verify("creationix", commit)
end)()
