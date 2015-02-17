
local db = require('../lib/db')("test")
p(db)

local hash = db.save("blob", "Hello World")
p(hash)
p(db.load(hash))
db.write("creationix", "git/foo", "0.2.3", hash)
hash = db.save("tree", {})
p(hash)
p(db.load(hash))
for hash in db.hashes() do
  p(hash)
end
db.write("creationix", "git", "3.2.1", hash)
for author in db.authors() do
  for tag in db.tags(author) do
    for version in db.versions(author, tag) do
      p(author, tag, version)
    end
  end
end

db.putKey("creationix", "213412341234", "test data\n")
p(db.readKey("creationix", "wrong key"), db.readKey("creationix", "213412341234"))
db.putKey("creationix", "092348509283450928", "test data\n")
db.putKey("creationix", "2348750423957029", "test data\n")
for fingerprint in db.fingerprints("creationix") do
  p(fingerprint)
end
db.revokeKey("creationix", "213412341234")

db.setEtag("bob", '"12342"')
p(db.getEtag("bob"))
db.setEtag("bob", '"542545"')
p(db.getEtag("bob"))

db.addOwner("luvit", "creationix")
db.addOwner("luvit", "rphillips")
db.addOwner("luvit", "rjemanuel")

for owner in db.owners("luvit") do
  p(owner)
end

db.removeOwner("luvit", "creationix")

local kind
kind, hash = db.import("app")
p(kind, hash)
db.export(hash, "test/app2")
