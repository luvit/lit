return {
  name = "luvit/lit",
  version = "2.0.10-1",
  homepage = "https://github.com/luvit/lit",
  description = "The Luvit Invention Toolkit is a luvi app that handles dependencies and luvi builds.",
  tags = {"lit", "meta"},
  license = "Apache 2",
  author = { name = "Tim Caswell" },
  luvi = {
    version = "2.1.1",
    flavor = "regular",
  },
  dependencies = {
    "luvit/require@1.2.1",
    "luvit/pretty-print@1.0.2",
    "luvit/http-codec@1.0.0",
    "luvit/json@2.5.0",
    "creationix/coro-fs@1.3.0",
    "creationix/coro-net@1.1.1",
    "creationix/coro-http@1.1.0",
    "creationix/coro-tls@1.2.0",
    "creationix/coro-wrapper@1.0.0",
    "creationix/coro-spawn@0.2.0",
    "creationix/coro-split@0.1.0",
    "creationix/hex-bin@1.0.0",
    "creationix/semver@1.0.4",
    "creationix/git@2.0.2",
    "creationix/prompt@1.0.3",
    "creationix/ssh-rsa@1.0.0",
    "creationix/websocket-codec@1.0.5",
  },
  files = {
    "commands/README",
    "**.lua",
    "!test*"
  }
}
