return {
  name = "creationix/lit",
  version = "0.9.9",
  dependencies = {
    "luvit/require@0.1.0",
    "creationix/pretty-print@0.1.0",
    "creationix/coro-fs@1.2.3",
    "creationix/coro-tcp@1.0.3",
    "creationix/coro-tls@1.1.0",
    "creationix/coro-wrapper@0.1.0",
    "creationix/hex-bin@1.0.0",
    "creationix/semver@1.0.1",
    "creationix/git@0.1.0",
    "creationix/prompt@1.0.0",
    "creationix/ssh-rsa@0.1.2",
    "creationix/http-codec@0.1.4",
    "creationix/websocket-codec@1.0.0",
    "creationix/json@2.5.1",
  },
  files = {
    "commands/README",
    "**.lua",
    "!test*"
  }
}
