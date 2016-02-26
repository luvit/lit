return {
  name = "luvit/lit",
  version = "3.2.1",
  homepage = "https://github.com/luvit/lit",
  description = "The Luvit Invention Toolkit is a luvi app that handles dependencies and luvi builds.",
  tags = {"lit", "meta"},
  license = "Apache 2",
  author = { name = "Tim Caswell" },
  luvi = {
    version = "2.6.1",
    flavor = "regular",
  },
  dependencies = {
    "luvit/pretty-print@2.0.0",
    "luvit/http-codec@2.0.0",
    "luvit/json@2.5.2",
    "luvit/resource@2.0.0",
    "luvit/secure-socket@1.0.0",
    "creationix/coro-fs@2.2.0",
    "creationix/coro-net@2.1.0",
    "creationix/coro-http@2.1.0",
    "creationix/coro-wrapper@2.0.0",
    "creationix/coro-spawn@2.0.0",
    "creationix/coro-split@2.0.0",
    "creationix/coro-websocket@1.0.0",
    "creationix/semver@2.0.0",
    "creationix/git@2.0.7",
    "creationix/prompt@2.0.0",
    "creationix/ssh-rsa@2.0.0",
    "creationix/websocket-codec@2.0.0",
  },
  files = {
    "commands/README",
    "**.lua",
    "!test*"
  }
}
