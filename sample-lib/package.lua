{
  name = "baz",
  version = "1.4.2",

  files = {
    "**/*.lua",
    "**/*.png",
    "maps/**",
    "!icons/store-icon.png"
  },

  deps = {
    foo = "0.2.1",
    bar = "1.2.1",
  },
}
