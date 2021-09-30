-- This script is intended to be run by the CI, from the root directory
local packageMetadata = dofile("package.lua")
local requiredLuviVersion = packageMetadata.luvi.version -- In case of errors, the CI will abort (working as intended)

print(requiredLuviVersion)