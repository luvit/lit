exports.name = "creationix/ssh-rsa"
exports.version = "0.1.0"

local openssl = require('openssl')

local pkey = openssl.pkey
local bn = openssl.bn
local digest = openssl.digest.digest
local base64 = openssl.base64

local function encodePrefix(body)
  if string.byte(body, 1) >= 128 then
    body = '\0' .. body
  end
  local len = #body
  return string.char(bit.band(bit.rshift(len, 24), 0xff))
      .. string.char(bit.band(bit.rshift(len, 16), 0xff))
      .. string.char(bit.band(bit.rshift(len, 8), 0xff))
      .. string.char(bit.band(len, 0xff))
      .. body
end

local function decodePrefix(input)
  local len = bit.bor(
    bit.lshift(string.byte(input, 1), 24),
    bit.lshift(string.byte(input, 2), 16),
    bit.lshift(string.byte(input, 3), 8),
               string.byte(input, 4))
  return string.sub(input, 5, 4 + len), string.sub(5 + len)
end


-- Given two openssl.bn instances for e and n, return the ssh-rsa formatted string for public keys.
function exports.encode(e, n)
return encodePrefix("ssh-rsa")
    .. encodePrefix(e:totext())
    .. encodePrefix(n:totext())
end

-- Given a raw ssh-rsa key as a binary string, parse out e and n as openssl.bn instances
function exports.decode(input)
  local format, e, n
  format, input = decodePrefix(input)
  assert(format == "ssh-rsa")
  e, input = decodePrefix(input)
  n, input = decodePrefix(input)
  assert(input == "")
  return bn.text(e), bn.text(n)
end

-- Calculate an ssh style fingerprint from raw public data
function exports.fingerprint(data)
  local parts = {}
  local hash = digest("md5", data, true)
  for i = 1, #hash do
    parts[i] = string.format("%02x", string.byte(hash, i))
  end
  return table.concat(parts, ":")
end

-- Calculate the public key data from an rsa private key file
function exports.loadPrivate(data)
  local key = pkey.read(data, true)
  local rsa = key:parse().rsa:parse()
  return exports.encode(rsa.e, rsa.n)
end

-- Extract the raw data from a public key file.
function exports.loadPublic(data)
  error("TODO: Implement")
end

function exports.writePublic(data)
  return "ssh-rsa " .. base64(data):gsub("\n", "")
end

function exports.sign(body, privateKey)

  -- Extract e and n from the private RSA key to build the ssh public key
  local rsa = privateKey:parse().rsa:parse()
  -- Encode in ssh-rsa format
  local data = exports.encode(rsa.e, rsa.n)
  -- And digest in ssh fingerprint format
  local fingerprint = exports.fingerprint(data)

  -- Sign the message using a sha256 message digest
  local sig = privateKey:sign(body, "sha256")
  return body ..
    "-----BEGIN RSA SIGNATURE-----\n" ..
    "Format: sha256-ssh-rsa\n" ..
    "Fingerprint: " .. fingerprint .. "\n\n" ..
    base64(sig) ..
    "-----END RSA SIGNATURE-----\n"
end

-- Given a raw body, a raw signature (PEM encoded with metadata), and a
-- publicKey instance, verify a signature.
function exports.verify(body, signature, publicKey)
  -- TODO: really verify
  return true
end
