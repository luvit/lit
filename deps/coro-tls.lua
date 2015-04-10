exports.name = "creationix/coro-tls"
exports.version = "1.1.2"

local openssl = require('openssl')
local bit = require('bit')

-- Given a read/write pair, return a new read/write pair for plaintext
exports.wrap = function (read, write, options)
  if not options then
    options = {}
  end

  local ctx = openssl.ssl.ctx_new("TLSv1_2")

  local key, cert, ca
  if options.key then
    key = assert(openssl.pkey.read(options.key, true, 'pem'))
  end
  if options.cert then
    cert = assert(openssl.x509.read(options.cert))
  end
  if options.ca then
    ca = assert(openssl.x509.read(options.ca))
  end
  if key and cert then
    assert(ctx:use(key, cert))
  end
  if ca then
    local store = openssl.x509.store:new()
    assert(store:add(ca))
    ctx:cert_store(store)
  else
    ctx:verify_mode({"none"})
  end

  ctx:options(bit.bor(
    openssl.ssl.no_sslv2,
    openssl.ssl.no_sslv3,
    openssl.ssl.no_compression))
  local bin, bout = openssl.bio.mem(8192), openssl.bio.mem(8192)
  local ssl = ctx:ssl(bin, bout, false)

  local function flush()
    while bout:pending() > 0 do
      write(bout:read())
    end
  end

  -- Do handshake
  while true do
    if ssl:handshake() then break end
    flush()
    bin:write(read())
  end

  local done = false
  local function shutdown()
    if done then return end
    done = true
    ssl:shutdown()
    flush()
    write()
  end

  local function plainRead()
    while true do
      local chunk = ssl:read()
      if chunk then return chunk end
      local cipher = read()
      if not cipher then return end
      bin:write(cipher)
    end
  end

  local function plainWrite(plain)
    if not plain then
      return shutdown()
    end
    ssl:write(plain)
    flush()
  end

  return plainRead, plainWrite

end
