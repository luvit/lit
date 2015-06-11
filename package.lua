return {
  name = "luvit/lit",
  version = "2.0.2",
  homepage = "https://github.com/luvit/lit",
  description = "The Luvit Invention Toolkit is a luvi app that handles dependencies and luvi builds.",
  tags = {"lit", "meta"},
  license = "Apache 2",
  author = { name = "Tim Caswell" },
  luvi = {
    version = "2.1.0",
    flavor = "regular",
  },
  dependencies = {
    "luvit/require@1.2.0",
    "luvit/pretty-print@1.0.2",
    "luvit/http-codec@1.0.0",
    "luvit/json@2.5.0",
    "creationix/coro-fs@1.2.4",
    "creationix/coro-tcp@1.0.5",
    "creationix/coro-http@1.0.7",
    "creationix/coro-tls@1.2.0",
    "creationix/coro-wrapper@1.0.0",
    "creationix/hex-bin@1.0.0",
    "creationix/semver@1.0.3",
    "creationix/git@2.0.0",
    "creationix/prompt@1.0.3",
    "creationix/ssh-rsa@1.0.0",
    "creationix/websocket-codec@1.0.3",
  },
  files = {
    "commands/README",
    "**.lua",
    "!test*"
  }
}
