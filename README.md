# Luvit Invention Toolkit

Lit is a toolkit designed to make working in the new [luvit][] 2.0 ecosystem
easy and even fun.

 - Lit powers the central repository at `wss://lit.luvit.io/`.
 - Lit is used to publish new packages to the central repository.
 - Lit is used to download and install dependencies into your local tree.
 - Lit can be used to compile [luvi][] apps from folders or zip files into
   self-executing binaries.

Lit is also a luvi app and library itself and bootstraps fairly easily.

## Installing Lit

In most cases, you just want to install lit as quickly as possible, possibly
in a `Makefile` or `make.bat` in your own library or app.

We maintain several [binary releases of
luvi](https://github.com/luvit/luvi/releases) to ease bootstrapping of lit and
luvit apps.

The following platforms are supported:

 - Windows (amd64)
 - FreeBSD 10.1 (amd64)
 - Raspberry PI (armv6)
 - Raspberry PI 2 (armv7)
 - Ubuntu 14.04 (x86_64)
 - Ubuntu 14.04 (i686)
 - OSX Yosemite (x86_64)

On unix, download the [install script](./get-lit.sh) and pipe to `sh`:

```sh
curl -L https://github.com/luvit/lit/raw/master/get-lit.sh | sh
```

If you're on Windows, We've thought of you as well.  Simply download and run
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
lit, it will build itself using the zip file as both code and input data.

When done, you will have a `lit` or `lit.exe` executable in your directory
that you can put somewhere in your path to install globally.

#### Building From Source

If the pre-built luvi binaries don't work on your machine, you can always build
[luvi from source](https://github.com/luvit/luvi#building-from-source).

Once you have luvi, building lit is simple:

```sh
> curl -L https://lit.luvit.io/packages/luvit/lit/latest.zip > lit.zip
> luvi lit.zip -- make lit.zip
```

Or you can clone lit from git and use the Makefile which will do the same thing
but use the files in the git clone.

```sh
> git clone --recursive git@github.com:luvit/lit.git
> cd lit
> make # If using official luvi binary
```

If you're using a custom built luvi binary instead of the official ones, you'll
need to manually run the make step with something like:

```sh
# $CUSTOM_LUVI is the path to your custom luvi binary.
> $CUSTOM_LUVI . -- make . ./lit $CUSTOM_LUVI
```

Once you have lit built, you'll want to install it somewhere in your path. (For
example `/usr/local/bin/`.)

```sh
> sudo install lit /usr/local/bin
```

## Command-Line Interface

Lit is a multi-functionality toolkit, it has many groups of commands via it's
CLI.

#### `lit help`

This will print a [high-level cheatsheet](./commands/README) of all the commands
in the interface to your terminal.

#### `lit version`

This simple command will print the lit version and exit.  It's useful to verify
which version of lit you have installed from a script.

#### `lit init`

This will run through a series of questions that will help you scaffold
out either
a `init.lua` file (used for simple packages) or a `package.lua` file
(used for more complicated or advanced projects).

### Local Configuration

These commands are for working with your local lit config file.

#### `lit auth username`

This command is used to authenticate as a github user.  It assumes you have a
RSA private key located at `$HOME/.ssh/id_rsa` and downloads your public keys
from github looking for one that matches the private key on the disk.  Once
verified you are the person you claim to be, this private key will be used to
sign packages you create to be published.

#### `lit up [url]`

By default lit is configured to use `wss://lit.luvit.io` as it's upstream
repository.  You can set a new custom upstream here.  If you're down (because of
`lit down`) this will bring you back online.  If the url is ommitted, the
`defaultUpstream` in your config will be used.

When online, lit will check the upstream when looking for package matches and
download and cache any new data on demand.

#### `lit down`

If your internet connection is slow or unreliable, you can use lit in offline
mode.  This will skip all calls to the upstream and work as a standalone
database using your cache.  This works surprisingly well once the packages you
commonly use are cached locally.

#### `lit config`

This simple helper will dump the contents of your config file for easy viewing

### Package Management

Lit's primary usage is probably as a package manager and client to the package
repository.

#### `lit add path*`

Given one or more paths to modules (folders or files containing lit metadata),
lit will read the metadata, import the file or folders into the database and
create a tagged release (signing if you're authenticated).

These packages can then be later published to an upstream or installed locally
in some other folder.

#### `lit publish path*`

Publish will first run `lit add path*` to ensure the latest version is imported
into the database.  It will then iterate over the local versions and upload any
that aren't yet on the upstream.

#### `lit install`

Running `lit install` in a folder containing lit metadata will install all it's
dependencies recursivly to the local `deps` folder.  If any of the
dependencies already exist there, they will be skipped, even if there is a new
version in the database.

#### `lit install names*`

You can also install one or more lit packages directly by name without setting
up a metadata file.

For example, this will install the latest version of `creationix/git` to modules
(even if there is something already there)

```sh
> lit install creationix/git
```

#### `lit sync`

If you like to work offline a lot, it's useful to run `lit sync` when online to
make sure the cached packages in your local database have the latest versions
cached.

Here is an example of going inline, checking for updates and then going back
offline.

```sh
> lit up
> lit sync
> lit down
```

### Upstream Organization Management

By default, you can only publish to upstream prefixes that match your github
username, but you can also publish to github organization names if you've set as
an other of that org in the lit upstream.

#### `lit claim org`

If you're a public member of an org on github, you can add yourself as an owner
to the corresponding org in the lit upstream.

#### `lit share org username`

Once you're an owner, you can add anyone as collaborators and co-owners with the
share command.

#### `lit unclaim org`

You can remove yourself from the list of owners with this command.

### Execution and Packaging

Luvi apps can be run and created using the `luvi` tool directly, but lit
provides easier interfaces to this and adds new functionality.

#### `lit make path/to/app [target]`

When you're ready to package your luvi app into a single binary, you can use
lit's make command.  This is more than simply setting `LUVI_TARGET`.  It will
read the `package.lua` metadata to get the name of the target.  Also it will
inject any missing dependencies into the bundle embedded in the executable.

Also the `package.lua` can contain a white-list of black-list of files to
include in the final bundle.  See examples in
[luvit](https://github.com/luvit/luvit/blob/luvi-up/package.lua) and
[lit](https://github.com/luvit/lit/blob/master/package.lua).

For example, lit's own bootstrap uses a combination of `LUVI_APP` and `lit make`
to build itself with nothing more than the luvi executable and a zip file
containing lit's source.

```sh
> luvi lit.zip -- make lit.zip
```

This will run the app contained in lit.zip passing in the arguments `make` and
`lit.zip`.  The `make` will trigger lit's make command and it will build a lit
executable from the contents of the zip file, installing any dependencies not
found in the zip.

### Lit Server

It's trivial to setup your own caching proxy or private repository of lit
packages.  Simply install lit on the server and run `lit serve`.  If you have
an upstream configured this server will act as a caching proxy.  Any requests
not found locally will be fetched from the upstream and cached locally.  Any
packages published locally will be kept local (private).

It's highly encouraged to setup such proxies if you have deployments that
depend on lit packages.  Never use the public repository directly for
repetitive and/or mission critical scripts.

The server listens on port `4822` by default.

```
> lit serve
lit version: 0.9.8
command: serve
load config: /home/tim/.litconfig
```

## Lit as a Library

Also you can use lit as a library via it's core interface.

This interface is is documented in [The libs README](./libs/README).

## REST API

Lit servers export a simple REST based interface for browsing the package contents.

This is a simple rest API for reading the remote database over HTTP.
It uses hypermedia in the JSON responses to make linking between requests simple.

The API for the main lit repository can be found at https://lit.luvit.io/

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

## Package Metadata

Lit packages need some form of metadata embedded in the lua files.  Packages can
be either single lua files or directories containing many files.  If your
library is a single file, simply set `name` and `version` and optionally
`dependencies` at the top of your file in a comment block wrapped with
`--[[lit-meta ... ]]`.  It will then be able to be imported into lit and
published to the repository.

For more complex packages, lit will search first in `package.lua` and then in
`init.lua`. The first file found will need to export or return a table
containing the `name`, `version` and `dependencies` metadata.

Here is an example of a single-file package

```lua
-- bad-math.lua
-- Dead simple library
--[[lit-meta
  name = "creationix/bad-math"
  version = "0.0.1"
]]

function add(a, b)
  return a - b
end

return { add = add }
```

This can then be published with `lit publish bad-math.lua`, it can be installed
with `lit install creationix/bad-math.lua` and dependend on with a
`dependencies` entry of `creationix/bad-math@0.0.1`.

If this was in a larger package, it could have a package.lua containing:

```lua
-- bad-math/package.lua
return {
  name = "creationix/bad-math",
  version = "0.0.1",
}
```

This could be published with `lit publish bad-math`.

## Internals

Lit is written in lua and uses the same system platform as the luvit project,
but is has a very different I/O style.  Instead of using callbacks and event
emitters, it uses coroutines so that code can be written with simple blocking
I/O, but still maintain the abilities of a non-blocking event loop.

Lit internally uses a git compatable database on disk for storing packages and
release tags.  The releases are actual git tags at
`refs/tags/$username/$name/v$version`.  These point to annotated tags that
contain an RSA signature (signed by the user's SSH private key as used on
github).  These tags then point directly to either trees or blobs.  Git commits
are never used in this system.

The network protocol is based on websockets.  The entire protocol is safe to use
in the open and doesn't require TLS for security since everything is verified
using SHA1 git hashes and signed and verified using RSA.  However, the client
and the central repository do support communication over TLS for clients on
networks containing HTTP proxies that break normal communication.

If you experience troubles on your company network, try setting your `upstream`
and `defaultUpstream` in your `.litconfig` to `wss://lit.luvit.io/`.  The cert
is invalid, but that doesn't matter here since we're simply trying to confuse
the proxy and not gain security from the socket.

Both the server and client query github using a REST API to get the public keys
of users when verifying signatures in package tags.  These keys are cached
locally inside the git database under `keys/$username/$fingerprint`.  Also
organization membership is stored under keys at `keys/$orgname.owners` in a
newline delimited file of usernames.

For full details read the source.  The libs folder has a nice [internal
README](./libs/README) to get you started.

[luvit]: https://github.com/luvit/luvit/
[luvi]:https://github.com/luvit/luvi/
