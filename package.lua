return {
  name = "luvit/lit",
  version = "1.2.1",
  luvi = {
    version = "2.0.5",
    flavor = "regular",
  },
  dependencies = {
    "luvit/require@1.1.0",
    "luvit/pretty-print@1.0.1",
    "luvit/http-codec@1.0.0",
    "luvit/json@1.0.0",
    "creationix/coro-fs@1.2.3",
    "creationix/coro-tcp@1.0.5",
    "creationix/coro-http@1.0.7",
    "creationix/coro-tls@1.1.4",
    "creationix/coro-wrapper@1.0.0",
    "creationix/hex-bin@1.0.0",
    "creationix/semver@1.0.2",
    "creationix/git@1.0.1",
    "creationix/prompt@1.0.3",
    "creationix/ssh-rsa@1.0.0",
    "creationix/websocket-codec@1.0.2",
  },
  files = {
    "commands/README",
    "**.lua",
    "!test*"
  }
}
