return {
  name = "creationix/weblit",
  version = "2.1.1",
  dependencies = {
    "creationix/weblit-app@2.1.0",
    "creationix/weblit-auto-headers@2.0.2",
    "creationix/weblit-etag-cache@2.0.0",
    "creationix/weblit-logger@02.0.0",
    "creationix/weblit-static@2.0.0",
    "creationix/weblit-websocket@2.1.0",
  },
  files = {
    "package.lua",
    "init.lua",
  },
  description = "This Weblit metapackage brings in all the official Weblit modules.",
  tags = {"weblit", "meta"},
  license = "MIT",
  author = { name = "Tim Caswell" },
  homepage = "https://github.com/creationix/weblit",
}
