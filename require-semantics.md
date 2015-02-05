# Lit's Require System

Lit, being a package manager, also bundles it's own module loader module for lua.  This document lays out how the system works.

## Relative paths

When a module requires another module with a string starting with a `.` or `..`, it is known as a relative require.  This is used for intra-package requires.  The path is resolved relative to the path of the module making the require call.  So, for example if `foo/bar.lua` contained the expression `require("./baz.lua")`, it would resolve to `foo/baz.lua`.  This feature works independent of the absolute path to the `bar.lua` file and thus enables entire trees of modules to be moved around without changing any internal require linkage.

## System paths

All other requires are considered system paths for external modules that are not part of the calling package.

## Virtual File System

...
