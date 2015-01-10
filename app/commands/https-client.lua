local tcp = require('creationix/coro-tcp')
local httpCodec = require('creationix/http-codec')
local tlsWrap = require('../lib/tls-wrap')
local wrapper = require('../lib/wrapper')

local read, write = assert(tcp.connect("luvit.io", "443"))

read, write = tlsWrap(read, write)

read = wrapper.reader(read, httpCodec.decoder())
write = wrapper.writer(write, httpCodec.encoder())

write({
  method = "GET",
  path = "/",
  {"Host", "luvit.io"}
})
for item in read do
  p(item)
end
write()
