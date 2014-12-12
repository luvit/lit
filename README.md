# Lit - Luvit Package Manager

This project is a command-line client and server for sharing luvit modules.

The server listens on a TCP port and speaks a custom sync protocol.

Message integrity is implemented via the nature of content addressable storage
using git compatable hashes of blobs, trees, and annotated tags.  It's
impossible to change any data without affecting the hashes of all parent nodes
in the graph (assuming you don't discover a way to create sha1 collisions within
the git format constraints).

Reading from the server is anonymous and has zero authentication.  Clients
simply query the server for things like list of package versions for a specefic
package, list of package names that match a search, list of authors, packaged by
a author, etc.

Also clients can get the hash to an rsa signed tag for a package release.  From
there the client can request the object for that tag, download the tag and
verify the RSA signature externally.  This way you know exactly who wrote the
code you're downloading and a company could keep a list of authorized package
authors they trust.  By default the client will trust any package where the
signer is the package owner and the signature verifies.

Initially verification will be done via dowloading public keys using github's
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

## Handshake

When a client makes a connection to a server, the following handshake is made:

Client sends:

    lit?0,1\n

meaning "Do you speak lit protocol versions 0 or 1?"

At which point the server will respond with:

    lit!0\n

meaning "Yes I do, Let's speak version 0!"

This way as future modifications to the protocol are added, clients and servers
can easily and quickly negotiate what versions they implement.  This document is
version 0.

## Binary Encoding

The network protocol consists of a stream of self-framed messages.

### WANT - 10xxxxxx (groups of 20 bytes)

`xxxxxx` is number of wants - 1.

This command is to tell the other end you want several hashes.  It's a bulk
request for requesting up to 64 hashes at a time.  Note that the number of
hashes is the value of `xxxxxx` + 1.

For example sending the hash `9012ffdba8018cf1f7a9b77a3145a459d40fa125` would
be:

    10000000 90 12 ff db a8 01 8c f1 f7 a9 b7 7a 31 45 a4 59 d4 0f a1 25

### SEND - 11Mxxxxx [Mxxxxxxx] data

(M) is more flag, x is variable length unsigned int.

This command is for
sending an object to the remote end of the pair.  Clients send then publishing a
new package and servers send then clients are downloading a package.

The hash isn't included, but it calculated by the receiving end.  This way there
can never be hash/value mismatches.  If a value is modified in transit, the hash
won't match and the receiver will reject it.  You can only send a value the
other side has asked for explicitly or you know they are expecting.

For example the binary message `"Hello World\n"`, would be encoded as:

    11001100 48 65 6c 6c 6f 20 57 6f 72 6c 64 0a

#### QUERY - '?' query '\n\n'

A query is simply a '?' byte followed by double newline..  The
string is assumed to be UTF-8 encoded. and has it's whitespace trimmed off both
ends before processing.

#### REPLY - '!' reply '\n\n'

Reply looks just query, but with a '!' byte prefix.

## Query System

The low-level WANT/SEND commands are for syncing binary objects between two
nodes, but the high-level QUERY/REPLY commands are for deciding what a client
wants to download from a server.

For example, if a client wants to get the release hash for `creationix/jack` at
version matching semver 0.1.2 they will send the query `"match creationix/jack 0.1.2"`
and the server will reply with `"0.1.2
59d6ef82e7bbb7b2d585c3680d3207c3a1a97be4"`.  If the tag didn't exist or the range
didn't match anything, the reply would be empty.  If the version is omitted, the
newest version will be returned.

    > ? match creationix/jack 0.1.2
    >>
    !0.1.2 59d6ef82e7bbb7b2d585c3680d3207c3a1a97be4
    > ? match creationix/jack
    >>
    !0.1.2 59d6ef82e7bbb7b2d585c3680d3207c3a1a97be4

Other queries can be added later like package name searches or metadata
searches.
