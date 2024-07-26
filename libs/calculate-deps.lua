--[[

Copyright 2014-2015 The Luvit Authors. All Rights Reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS-IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

--]]

local gte = require('semver').gte
local log = require('log').log
local exec = require('exec')
local queryDb = require('pkg').queryDb
local colorize = require('pretty-print').colorize
local queryGit = require('pkg').queryGit
local normalize = require('semver').normalize

local processDeps
local db, deps, configs

local GIT_SCHEMES = {
  "^https?://", -- over http/s
  "^ssh://", -- over ssh
  "^git://", -- over git
  "^ftps?://", -- over ftp/s
  "^[^:]+:", -- over ssh
}

local function isGit(dep)
  for i = 1, #GIT_SCHEMES do
    if dep:match(GIT_SCHEMES[i]) then
      return true
    end
  end
  return false
end

local function resolveDep(alias, dep)
  -- match for author/name@version
  local name, version = dep:match("^([^@]+)@?(.*)$")
  -- resolve alias name, in case it's a number (an array index)
  if type(alias) == "number" then
    alias = name:match("([^/]+)$")
  end

  -- make sure owner is provided
  if not name:find("/") then -- FIXME: this does match on `author/` or `/package`
    error("Package names must include owner/name at a minimum")
  end

  -- resolve version
  if #version ~= 0 then
    local ok
    ok, version = pcall(normalize, version)
    if not ok then
      error("Invalid dependency version: " .. dep)
    end
  else
    version = nil
  end

  -- check for already installed packages
  local meta = deps[alias]
  if meta then
    -- is there an alias conflict?
    if name ~= meta.name then
      local message = string.format("%s %s ~= %s",
        alias, meta.name, name)
      log("alias conflict", message, "failure")
    -- is there a version conflict?
    elseif version and not gte(meta.version, version) then
      local message = string.format("%s %s ~= %s",
        alias, meta.version, version)
      log("version conflict", message, "failure")
    -- re-process package dependencies if everything is ok
    else
      processDeps(meta.dependencies)
    end
    return
  end

  -- extract author and package names from "author/package"
  -- and match against the local db for the resources
  -- if not available locally, and an upstream is set, match the upstream db
  local author, pname = name:match("^([^/]+)/(.*)$")
  local match, hash = db.match(author, pname, version)

  -- no such package has been found locally nor upstream
  if not match then
    error("No such "
      .. (version and "version" or "package") .. ": "
      .. name
      .. (version and '@' .. version or ''))
  end

  -- query package metadata, and mark it for installation
  local kind
  meta, kind, hash = assert(queryDb(db, hash))
  meta.db = db
  meta.hash = hash
  meta.kind = kind
  deps[alias] = meta

  -- handle the dependencies of the module
  processDeps(meta.dependencies)
end

-- TODO: implement git protocol over https, to be used in case `git` cli isn't available
-- TODO: implement someway to specify a branch/tag when fetching
-- TODO: implement handling git submodules, or shall we not?
local function resolveGitDep(url)
  -- fetch the repo tree, don't include any tags
  log("fetching", colorize("highlight", url))
  local _, stderr, code = exec("git", "--git-dir=" .. configs.database,
    "fetch", "--no-tags", "--depth=1", url)

  -- was the fetch successful?
  if code ~= 0 then
    if stderr:match("^ENOENT") then
      error("Cannot find git. Please make sure git is installed and available.")
    else
      error((stderr:gsub("\n$", "")))
    end
  end

  -- load the fetched module tree
  local raw = db.storage.read("FETCH_HEAD")
  local hash = raw:match("^(.-)\t\t.-\n$")
  assert(hash and #hash ~= 0, "Unable to retrieve FETCH_HEAD\n" .. raw)
  hash = db.loadAs("commit", hash).tree

  -- query module's metadata, and match author/name
  local meta, kind
  meta, kind, hash = queryGit(db, hash)
  assert(meta, "Unable to find a valid package")
  local author, name = meta.name:match("^([^/]+)/(.*)$")

  -- check for installed packages and their version
  local oldMeta = deps[name]
  if oldMeta and not gte(oldMeta.version, meta.version) then
    local message = string.format("%s %s ~= %s",
      name, oldMeta.version, meta.version)
    log("version conflict", message, "failure")
    return
  end

  -- create a ref/tags/author/name/version pointing to module's tree
  db.write(author, name, meta.version, hash)

  -- mark the dep for installation
  meta.db = db
  meta.hash = hash
  meta.kind = kind
  deps[name] = meta

  -- handle the dependencies of the module
  processDeps(meta.dependencies)
end

function processDeps(dependencies)
  if not dependencies then return end
  -- iterate through dependencies and resolve each entry
  for alias, dep in pairs(dependencies) do
    if isGit(dep) then
      resolveGitDep(dep)
    else
      resolveDep(alias, dep)
    end
  end
end

return function (core, depsMap, newDeps)
  -- assign gitDb and depsMap as upvalues to be visible everywhere
  -- then start processing newDeps
  db, deps, configs = core.db, depsMap, core.config
  processDeps(newDeps)

  -- collect all deps names and log them
  local names = {}
  for k in pairs(deps) do
    names[#names + 1] = k
  end
  table.sort(names)
  for i = 1, #names do
    local name = names[i]
    local meta = deps[name]
    log("including dependency", string.format("%s (%s)",
      colorize("highlight", name), meta.path or meta.version))
  end

  return deps
end
