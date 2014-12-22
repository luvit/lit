
# Upstream interface

Upstream has access to storage so it can read to and write from it.

## upstream.push(hash) -> ref

Push a hash and dependents recursivly to upstream server.

Internally this does the following:

    Client: SEND tagObject

    Server: WANT objectHash

    Client: SEND object

    Server: WANT ...
    Server: WANT ...
    Server: WANT ...

    Client: SEND ...
    Client: SEND ...
    Client: SEND ...

    Server: CONF tag

The client sends an unwanted tag which will trigger a sync from the server.
The client, without waiting also sends a VERIFY request requesting the server
tell it when it has the tag and it's children.  The server then fetches and
objects it's missing.  When done, server confirms tagHash to the client.

If a server already has an object when receiving a graph, it will scan it's
children for missing bits from previous failed attemps and resume there.

Only after confirming the entire tree saved will the server write the tag and
seal the package.

## upstream.pull(ref) -> hash

Pull a hash and dependents recursivly from upstream server.

This is essentially the same command, but reversed.

    Client: PULL tag

    Server: SEND tagObject

    Client: WANT objectHash

    Server: SEND object

    Client: WANT ...
    Client: WANT ...
    Client: WANT ...

    Server: SEND ...
    Server: SEND ...
    Server: SEND ...

The client knows locally when it has the entire tree and creates the local tag
sealing the package.  The client will also check deep for missing objects
before confirming a tree as complete.

## upstream.match(name, version) -> version, hash

Query a server for the best match to a semver

    Client: MATCH name version

    Server: REPLY version

----------------


11Mxxxxx Mxxxxxxx* SEND variable length binary data
10000000 WANT 20-bytes binary data

PULL name version
CONF name version
MATCH name version
REPLY version
ERROR message


CLIENT EVENTS:

TAG tag, emitted when the local storage finishes all the objects for a new tree.


