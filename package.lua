return {
  name = "luvit/lit",
  version = "1.1.2",
  luvi = {
    version = "2.0.1",
    flavor = "regular",
  },
  dependencies = {
    "luvit/require@1.0.1",
    "luvit/pretty-print@1.0.0",
    "luvit/http-codec@1.0.0",
    "luvit/json@1.0.0",
    "creationix/coro-fs@1.2.3",
    "creationix/coro-tcp@1.0.5",
    "creationix/coro-http@1.0.6",
    "creationix/coro-tls@1.1.2",
    "creationix/coro-wrapper@1.0.0",
    "creationix/hex-bin@1.0.0",
    "creationix/semver@1.0.1",
    "creationix/git@1.0.0",
    "creationix/prompt@1.0.2",
    "creationix/ssh-rsa@1.0.0",
    "creationix/websocket-codec@1.0.0",
  },
  files = {
    "commands/README",
    "**.lua",
    "!test*"
  }
}
