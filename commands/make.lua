local core = require('core')()
local uv = require('uv')
local pathJoin = require('luvi').path.join
local fs = require('coro-fs')
local import = require('import')
local getInstalled = require('get-installed')
local calculateDeps = require('calculate-deps')
local queryFs = require('pkg').query
local installDeps = require('install-deps')
local export = require('export')

-- 1 Import to db applying filter rules.
-- 2 Get extra dependencies sources from source fs
-- 3 Install dependencies to db tree getting new hash (using extra source).
-- 4 Export new hash to zip file or fs, with nativeOnly filter.
local source = uv.cwd()
local kind, hash = assert(import(core.db, fs, source, {"-build"}, true))
assert(kind == "tree", "Only tree packages are supported for now")
local meta = queryFs(fs, source)
local deps = getInstalled(fs, source)
calculateDeps(core.db, deps, meta.dependencies)
hash = installDeps(core.db, hash, deps)

export(core.db, hash, fs, "build")
--
--
-- local cwd = uv.cwd()
-- local source = args[2] and pathJoin(cwd, args[2])
-- local target = args[3] and pathJoin(cwd, args[3])
-- if not source or uv.fs_access(source, "r") then
--   core.make(source or cwd, target)
-- else
--   core.makeUrl(args[2], target)
-- end
--
