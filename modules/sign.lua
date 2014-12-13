local base64 = require('openssl').base64
local sshRsa = require('ssh-rsa')

return function (body, privateKey)

  -- Extract e and n from the private RSA key to build the ssh public key
  local rsa = privateKey:parse().rsa:parse()
  -- Encode in ssh-rsa format
  local data = sshRsa.encode(rsa.e, rsa.n)
  -- And digest in ssh fingerprint format
  local fingerprint = sshRsa.fingerprint(data)

  -- Sign the message using a sha256 message digest
  local sig = privateKey:sign(body, "sha256")
  return body ..
    "-----BEGIN RSA SIGNATURE-----\n" ..
    "Format: sha256-ssh-rsa\n" ..
    "Fingerprint: " .. fingerprint .. "\n\n" ..
    base64(sig) ..
    "-----END RSA SIGNATURE-----\n"
end
