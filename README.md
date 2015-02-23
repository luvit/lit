# Luvit Invention Toolkit

Lit is a toolkit designed to make working in the new [luvit][] 2.0 ecosystem
easy and even fun.  It serves multiple pusposes.  Lit is what run the central
package repository at `wss://lit.luvit.io/`.  It can be used to compile
[luvi][] apps from folders or zip files into self-executing binaries.  Lit is
used to publish new packages to the central repository and install
dependencies into your local tree.

Lit is also a luvi app and luvi library itself and bootstraps fairly easily.

## Installing Lit

In most cases, you just want to install lit as quickly as possible, possibly
in a `Makefile` or `make.bat` in your own library or app.

On unix, download the [install script](./get-lit.sh) and pipe to `sh`:

```sh
curl -L https://github.com/luvit/lit/raw/master/get-lit.sh | sh
```

Since lit is still young, I recommend not using `master` and instead using a
specified tag for your bootstrap scripts till we get past 1.0.0.

If you're on Windows, I've thought of you as well.  Simply download and run
the [powershell script](./get-lit.ps1).

In `cmd.exe` run:

```batch
PowerShell -NoProfile -ExecutionPolicy unrestricted -Command "iex ((new-object net.webclient).DownloadString('https://github.com/luvit/lit/raw/master/get-lit.ps1'))"
```

Or directly in powershell, run:

```powershell
iex ((new-object net.webclient).DownloadString('https://github.com/luvit/lit/raw/master/get-lit.ps1'))
```

Both these scripts will attempt to download a pre-compiled [luvi][] binary and
the source to lit as a zip file.  Then using the zip capabilities in luvi and
zip, it will build itself using the zip file as both code and input data.

When done, you will have a `lit` or `lit.exe` executable in your directory
that you can put somewhere in your path to install globally.

## Command-Line Interface

Lit is a multi-functionality toolkit, it has many groups of commands via it's CLI.

#### `lit help`

This will print a [high-level cheatsheet](./commands/README) of all the commands in the interface to your terminal.

#### `lit version`

This simple command will print the lit version and exit.  It's useful to verify which version of lit you have installed from a script.

### Local Configuration

These commands are for working with your local lit config file.

#### `lit auth username`

This command is used to authenticate as a github user.  It assumes you have a RSA private key located at `$HOME/.ssh/id_rsa` and downloads your public keys from github looking for one that matches the private key on the disk.  Once verified you are the person you claim to be, this private key will be used to sign packages you create to be published.

#### `lit up [url]`

By default lit is configured to use `wss://lit.luvit.io` as it's upstream repository.  You can set a new custom upstream here.  If you're down (because of `lit down`) this will bring you back online.  If the url is ommitted, the `defaultUpstream` in your config will be used.

When online, lit will check the upstream when looking for package matches and download and cache any new data on demand.

#### `lit down`

If your internet connection is slow or unreliable, you can use lit in offline mode.  This will skip all calls to the upstream and work as a standalone database using your cache.  This works suprizingly well once the packages you commonly use are cached locally.

#### `lit config`

This simple helper will dump the contents of your config file for easy viewing

### Package Management

Lit's primary usage is probably as a package manager and client to the package repository.

#### `lit add path*`

Given one or more paths to modules (folders or files containing lit metadata), lit will read the metadata, import the file or folders into the database and create a tagged release (signing if you're authenticated).

These packages can then be later published to an upstream or installed locally in some other folder.

#### `lit publish path*`

Publish will first run `lit add path*` to ensure the latest version is imported into the database.  It will then iterate over the local versions and upload any that aren't yet on the upstream.

#### `lit install`

Running `lit install` in a folder containing lit metadata will install all it's dependencies recursivly to the local `modules` folder.  If any of the dependencies already exist there, they will be skipped, even if there is a new version in the database.

#### `lit install names*`

You can also install one or more lit packages directly by name without setting up a metadata file.

For example, this will install the latest version of `creationix/git` to modules (even if there is something already there)

```sh
> lit install creationix/git`
```

#### `lit sync`

If you like to work offline a lot, it's useful to run `lit sync` when online to make sure the cached packages in your local database have the latest versions cached.

Here is an example of going inline, checking for updates and then going back offline.

```sh
> lit up
> lit sync
> lit down
```

### Upstream Organization Management

By default, you can only publish to upstream prefixes that match your github username, but you can also publish to github organization names if you've set as an other of that org in the lit upstream.

#### `lit claim org`

If you're a public member of an org on github, you can add yourself as an owner to the corresponding org in the lit upstream.

#### `lit share org username`

Once you're an owner, you can add anyone as collaborators and co-owners with the share command.

#### `lit unclaim org`

You can remove yourself from the list of owners with this command.

### Execution and Packaging

Luvi apps can be run and created using the `LUVI_APP` and `LUVI_TARGET` environment variables, but lit provides easier interfaces to this and adds new functionality.

#### `lit make path/to/app [target]`

When you're ready to package your luvi app into a single binary, you can use lit's make command.  This is more than simply setting `LUVI_TARGET`.  It will read the `package.lua` metadata to get the name of the target.  Also it will inject any missing dependencies into the bundle embedded in the executable.

Also the `package.lua` can contain a white-list of black-list of files to include in the final bundle.  See examples in [luvit](https://github.com/luvit/luvit/blob/luvi-up/package.lua) and [lit](https://github.com/luvit/lit/blob/master/package.lua).

For example, lit's own bootstrap uses a combination of `LUVI_APP` and `lit make` to build itself with nothing more than the luvi executable and a zip file containing lit's source.

```sh
> LUVI_APP=lit.zip luvi make lit.zip
```

This will run the app contained in lit.zip passing in the arguments `make` and `lit.zip`.  The `make` will trigger lit's make command and it will build a lit executable from the contents of the zip file, installing any dependencies not found in the zip.

#### `lit run args*`

If you're in the root of a luvi app, you can run it here.  The following two commands are basically the same:


Directly in luvi:

```sh
> LUVI_APP=. luvi arg1 arg2`
```

Using lit wrapper:

```sh
> lit run arg1 arg2
```

This is mostly for environments where setting temporary environment variables is less than ideal.

#### lit test

This is another convenience wrapper.  It is the same as `lit run` except is also sets a custom main to run.

```sh
> LUVI_APP=. LUVI_MAIN=tests/run.lua luvi
```

Is the same as:

```sh
> lit test
```

### Lit Server

It's trivial to setup your own caching proxy or private repository of lit packages.  Simply install lit on the server and run `lit serve`.  If you have an upstream configured this server will act as a caching proxy.  Any requests not found locally will be fetched from the upstream and cached locally.  Any packages published locally will be kept local (private).

It's highly encouraged to setup such proxies if you have deployments that depend on lit packages.  Never use the public repository directly for repetitive and/or mission critical scripts.


## Lit as a Library

Also you can use lit as a library via it's core interface.

This interface is is documented in [The lib README](./lib/README).

## REST API

Lit servers export a simple REST based interface for browsing the package contents.

This is a simple rest API for reading the remote database over HTTP.
It uses hypermedia in the JSON responses to make linking between requests simple.

```
GET / -> api json {
  blobs = "/blobs/{hash}"
  trees = "/trees/{hash}"
  packages = "/packages{/author}{/tag}{/version}"
}
GET /blobs/$HASH -> raw data
GET /trees/$HASH -> tree json {
 foo = { mode = 0644, hash = "...", url="/blobs/..." }
 bar = { mode = 0755, hash = "...", url="/trees/..." }
 ...
}
GET /packages -> authors json {
  creationix = "/packages/creationix"
  ...
}
GET /packages/$AUTHOR -> tags json {
  git = "/packages/creationix/git"
  ...
}
GET /packages/$AUTHOR/$TAG -> versions json {
  v0.1.2 = "/packages/creationix/git/v0.1.2"
  ...
}
GET /packages/$AUTHOR/$TAG/$VERSION -> tag json {
  hash = "..."
  object = "..."
  object_url = "/trees/..."
  type = "tree"
  tag = "v0.2.3"
  tagger = {
    name = "Tim Caswell",
    email = "tim@creationix.com",
    date = {
      seconds = 1423760148
      offset = -0600
    }
  }
  message = "..."
}
```

## Background Information

This section is slightly out of date, updates forthcoming.

The server listens on a TCP port and speaks a custom sync protocol.

Message integrity is implemented via the nature of content addressable storage
using git compatible hashes of blobs, trees, and annotated tags.  It's
impossible to change any data without affecting the hashes of all parent nodes
in the graph (assuming you don't discover a way to create sha1 collisions within
the git format constraints).

Reading from the server is anonymous and has zero authentication.  Clients
simply query the server for things like list of package versions for a specific
package, list of package names that match a search, list of authors, packaged by
a author, etc.

Also clients can get the hash to an rsa signed tag for a package release.  From
there the client can request the object for that tag, download the tag and
verify the RSA signature externally.  This way you know exactly who wrote the
code you're downloading and a company could keep a list of authorized package
authors they trust.  By default the client will trust any package where the
signer is the package owner and the signature verifies.

Initially verification will be done via downloading public keys using github's
web API.  Publishers will sign with the same ssh private key they use to push to
github.  In fact this will be the only constrained operation in the network
protocol.  While reads are anonymous, publishing a new package requires signing
the tag and publishing only to your subaccount.  The server will verify the
signature before accepting a tag or it's related object graph.

Later on we can add more signature schemes like PGP web of trust or github
organizations, but initially it will be limited to github user accounts.  This
will hit the 90% use case and is considerably less engineering effort.

The network protocol also includes commands for syncing objects between a
central server and the local database on the client's machine.  In this way, the
system will be as centralized or distributed as you wish, exactly the same way
git works. Though the network protocol itself is nothing like gits pack
protocol.

## Centralized and Distributed

Each instance of the lit system has a local database.  When lit is running on
online mode, it will check the  remote for updates and missing packages and
cache everything downloaded locally.

This node can then act as client or server.  Simply run `lit serve` to start a
local server.

To connect to a remote server use the `lit up` command.  By default it
connects to `lit.luvit.io`, but can be set to any custom server like `lit up
localcache.server`.  This way it's trivial to setup a caching proxy for a lan.
This is highly recommended for any continuous deployment systems to take
network pressure off the main server and to insulate yourself from outages in
the main server.  Also this means it's easy to setup your own custom
repositories that contain private code in addition to pulling from the public
repo.

Currently the client starts out in offline mode, so you'll need to `lit up`
before downloading any new packages.

## Network Protocol

The network protocol is a websocket subprotocol.  The main lit.luvit.io server
is listening on IPv4 and IPv6 on ws:// and wss://.

The core lit subprotocol doesn't require encryption since it verifies everything
using RSA signatures and SHA1 hashes.  The wss:// transport is for use in
networks where HTTP proxies break normal websocket traffic.

Within this websocket stream, there are binary and text frames.

### WANTS - 0x00, num, num * (groups of 20 bytes)

The first binary frame type is a list of hashes the sender wants.  The first
byte is a null byte.  The second is the number of hashes.  Then groups of 20
bytes follow for each hash in raw binary form.

### SEND - deflated raw data

When the sender wishes to send a git object, it simply sends the raw data
as deflated binary data.  Since deflate can't start with a null byte, this is
safe.

### ERROR - '\0', message

Errors are sent as text frames that start with a null byte.

### MESSAGE NAME, ' ', data

All other messages are send as plain text frames.  The name of the event is
the first part of the string up till the first space.  Everything following
the space is the data to this event.

### Examples

This is designed to allow manual queries using `wscat` in a terminal.

For example, here is a client asking an upstream for the best match to `creationix/git@0.1.0`:

    > match creationix/git 0.1.0
    reply 0.1.0 1462ea9bac27022e71db39b538b35b388a4873

When a client is uploading a package upstream, the entire conversation is
binary WANTS and SENDS, except for the final `done` sent by the server to
confirm it was all received and stored to persistent storage.

    Client: SEND tag object

    Server: WANTS hash to object in tag

    Client: SEND object

    Server: WANTS ... (blobs in tree not on server yet)

    Client: SEND ... (client sends all wants at once)
    Client: SEND ...
    Client: SEND ...

    (repeat till server has entire graph from tag)

    Server: "done acb2e4b9bf8b7a99e63b830de5d610af2e8d49\n"

Downloading from the server is similar, but in reverse and without the "done" message:

    Client: "match creationix/sample-lib\n"

    Server: "reply 0.1.1 acb2e4b9bf8b7a99e63b830de5d610af2e8d49\n"

    Client: WANTS acb2e4b9bf8b7a99e63b830de5d610af2e8d49 (tag hash)

    Server: SEND data for tag

    Client: WANTS ...

    Server: SEND ...
    Server: SEND ...
    Server: SEND ...

    (repeat till client has all missing objects)

The server will reject any "SEND" commands for objects it hasn't authorized.
Sending a tag that's signed by it's owner is allowed.  Then any dependent
objects on that tag's graph as requested by the server are authorized.

Clients likewise should reject objects from servers that they weren't
expecting.  Clients should also verify signatures in tag objects before asking
for it's contents.

Since the storage is content addressable, any files or folders already cached
from a related package won't be transferred again.  When uploading or
downloading a new package, only the changed blobs/trees will be transfered in
addition to the tag object.

## Storage

There are two storage backends.  One is implemented in pure lua and is
compatible with the git client.  This allows using tools like `git fsck` to
verify the sanity of the local database and allows storing mirrors on github.

This will create a tree structure like the following:

```
.
├── config
├── HEAD
├── objects
│   ├── 10
│   │   └── bda14b5d345a1a98ecfeed2d2478cb4b3d9ec4
│   ├── 3f
│   │   └── 34a3a73291a7ed72b9726a2ffc891419f3ff18
│   ├── 55
│   │   └── 7db03de997c86a4a028e1ebd3a1ceb225be238
│   ├── 8e
│   │   └── 7e2858b1734a9a846eb8b9ed91382dd290baed
│   ├── 94
│   │   └── acb2e4b9bf8b7a99e63b830de5d610af2e8d49
│   ├── ab
│   │   └── 626a6a7a67563e08486369d3eee0aba0ff47f8
│   ├── c9
│   │   └── ac958dae3e2f27af843956e64e6f37ec53f523
│   └── f5
│       └── 96188cbe1506da3e05626f6e25eee8a68b73cf
├── keys
│   └── creationix
│       ├── e4b9bf8b7a99e63b830de5d610af2e
│       └── etag
└── refs
    └── tags
        └── creationix
            └── greetings
                └── v0.0.1
```

This is a tiny repo containing a single small package, "creationix/greetings"
version 0.0.1.

It also contains the public key for creationix cached locally with the etag from github's REST api.

## CLI Interface

The main interface users will see is the command-line `lit` tool.

### Install

Normally, you use lit to install third-party modules into your app.

```sh
> lit install creationix/gamepad
lit version: 0.0.1
command: install creationix/gamepad
modules folder: /home/tim/Code/conquest/modules
cache version: none
remote version: 1.0.2
fetching: c9ac958dae3e2f27af843956e64e6f37ec53f523 creationix/gamepad@1.0.2
verifying signature: 0e:f3:5c:a2:9f:27:5e:ec:78:cc:a4:c7:a0:8b:a2:83
fetching: 10bda14b5d345a1a98ecfeed2d2478cb4b3d9ec4 /
fetching: 557db03de997c86a4a028e1ebd3a1ceb225be238 /main.lua
fetching: 94acb2e4b9bf8b7a99e63b830de5d610af2e8d49 /parser.lua
exporting: /home/tim/Code/conquest/modules/creationix/gamepad
done: success
```

This will search for a modules folder, check the local cache for a version that
matches, if not, it will use the remote repo to get a version.  Once found, it
will download the tag and verify the signature (caching the public key).

Once the package is verified, it will sync down all the missing objects the
local database doesn't have yet by sending the server WANT commands.

Once the local version has the entire graph for the tag, it will export the
files to the filesystem.

### Add

Before you can share a package with others, you need to first add it to your
local database.  This enables testing the install cycle without actually
sharing with the world yet.

```sh
> cd gamepad
> lit add
lit version: 0.0.1
command: add
package name: gamepad
package version: 0.5.4
importing: /home/tim/Code/gamepad
signing: 0e:f3:5c:a2:9f:27:5e:ec:78:cc:a4:c7:a0:8b:a2:83
done: success
```

The name is guessed based on the folder name, the git remote name, or the `name`
field in the local `package.lua` file.

The version is guessed based on the result of `git describe` or the `version`
field of `package.lua`.

The tree is imported recursively into the local database, a tag is created
containing the name and version.  This tag is then signed using the local
identity.

You can now install this package from any machine that uses this machine as the
upstream or any other project on the local machine.

### Auth

This command will update the `$HOME/.litconfig` (or `$APPDATA\litconfig` on
windows) file to contain your author information.  Currently this will be your
github username and the path to a local private rsa key that you have in your
public github profile.  It will verify the local key and make sure it matches
one of your keys online.

```sh
> lit auth
lit version: 0.0.1
command: auth
create config: /Users/tim/.litconfig
github name: creationix
ssh fingerprint: 8b:70:91:a9:39:02:68:c5:4b:b8:80:fe:b3:78:ec:3f
update config: /Users/tim/.litconfig
done: success

> cat ~/.litconfig
database: /Users/tim/.litdb.sophia
github name: creationix
upstream: lit.luvit.io
private key: /Users/tim/.ssh/id_rsa
storage: sophia
```

### Publish

Once you've run auth, you can publish packages to your upstream database.

```sh
> lit publish gamepad
lit version: 0.0.1
command: publish gamepad
cache version: 0.5.4
remote version: 0.5.3
sending: c9ac958dae3e2f27af843956e64e6f37ec53f523 creationix/gamepad@0.5.4
sending: 10bda14b5d345a1a98ecfeed2d2478cb4b3d9ec4 /
sending: 557db03de997c86a4a028e1ebd3a1ceb225be238 /main.lua
sending: 94acb2e4b9bf8b7a99e63b830de5d610af2e8d49 /parser.lua
done: success
```

You can only publish packages that you're already added to your local database.
But once it's added to your local database, you can publish any local packaged
you own.

### Sync

Once you've stored a package in your local database, future installs will look
there first and not bother checking online if a match is found locally.

This makes the offline experience much better, but it means you have to manually
run sync when you're online if you want to get updates.

Running a sync will grab the latest versions and latest semver matches of all
local packages in the db.

[luvit]: https://github.com/luvit/luvit/
[luvi]:https://github.com/luvit/luvi/
