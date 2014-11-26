{
  name = "baz",
  version = "1.4.2",

  files = {
    "art/*",
    "icons/*",
    "!icons/store-icon.png",
    "maps/*",
    "*.lua",
  },

  deps = {
    foo = "0.2.1",
    bar = "1.2.1",
  },
}
