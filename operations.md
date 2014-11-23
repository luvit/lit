Hash (path) -> hash - Fast hash calculation (used by import/export for effeciency)
Import (path) -> hash - Import a file or folder from disk
Export (path, hash)   - Export a hash to disk as file or folder

Has(hash) - check to see if we have a hash locally (used by send/get)
Send(hash) - Send a hash and all it's dependencies to a remote server
Get(hash)  - Get a hash and all it's dependencies from a remote server

dependencies
 - name @ version-range
 - name @ version-range

Use annotated tags to label releases

People publish to their own repos?
Main repo pulls in data from their repo (with assisted ping from user or poll)

Best-practices:
 - Changelog in tag
 - gpg sign when deploying
 - Tests
 - Docs
 - Semver (1+.x.x can be seen by others, 0.x.x not browsable)

Store ranges and direct dependencies in repo in package.json-like file

Use submodules for absolute deps with hard hashes

use gpg signatures for authentication


User account and project server

 - user accounts (tied to github oauth tokens)
 - projects (each project has a list of collaborators)
   - project can have external mirror to poll from?
   - projects list annotated tags for release versions

 Central repository server

 - Massive git database with custom tcp protocol for syncing git objects
 - Allows importing trees as long as they are tagged and signed by a project
 - anonymous read of any hashes


Sample tagged tree
t: foo v0.1.2
- a/
 - b
 - c
 - d/
  - e
  - f

- get versions for foo
- match against range to get concrete version
- request to sync tag foo v0.1.2

case1: empty local client (note trees are sent first)

-> WANT t*
<- t*, a/
-> WANT d/
<- d/
-> WANT e, f, b, c (note deeper nodes are requested first)
<- e, f, b, c

case2: local client has (b,c) already
-> WANT t*
<- t*, a/
-> WANT d/
<- d/
-> WANT e, f
<- e, f

case3: local has (d) already
-> WANT t*
<- t*, a/
-> WANT b, c
<- b, c

case4: local has (a) already

-> WANT t*
<- t*, a/

case5: client wants to upload a, server has none

-> GIVE t*
-> t*, a/
<- WANT d/
-> d/
<- WANT e, f, b, c
-> e, f, b, c
<- GOT t*

case5: client wants to upload a, server has (b, c)

-> GIVE t*
-> t*, a/
<- WANT d/
-> d/
<- WANT e, f
-> e, f
<- GOT t*

case5: client wants to upload a, server has (d)

-> GIVE t*
-> t*, a/
<- WANT b, c
-> b, c
<- GOT t*

case6: client wants to upload a, server has (a)

-> GIVE t*
-> t*, a/
<- GOT t*


Client commands
 - WANT hash(s)
 - SEND object
 - GIVE hash

Server commands
 - WANT hash(s)
 - SEND object
 - GOT hash

SEND is reply to WANT
GOT is reply to GIVE

Bidirectional deflate stream

Binary Encoding
SEND - 1Mxxxxxx [Mxxxxxxx] data
       (M) is more flag, x is variable length unsigned int
WANT - 01xxxxxx (groups of 20 bytes)
       (xxxxxx is number of wants)
GIVE - 00110000 (20 raw byte hash)
GOT  - 00110001 (20 raw byte hash)

WANT (4)
  edce9c4fce26d8123c001fa2626ced63216e0b25
  e641d10faa6cf78df0ea55c2db210b9eb286c6c9
  f0711aadc333e9c86a8f18da76f0ea968f776bae
  781dafe7db0685aadfea89cc3656dfddec6db29f
01000100(44)
  edce9c4fce26d8123c001fa2626ced63216e0b25
  e641d10faa6cf78df0ea55c2db210b9eb286c6c9
  f0711aadc333e9c86a8f18da76f0ea968f776bae
  781dafe7db0685aadfea89cc3656dfddec6db29f

GIVE edce9c4fce26d8123c001fa2626ced63216e0b25
00110000(30) edce9c4fce26d8123c001fa2626ced63216e0b25

GOT edce9c4fce26d8123c001fa2626ced63216e0b25
00110001(31) edce9c4fce26d8123c001fa2626ced63216e0b25
