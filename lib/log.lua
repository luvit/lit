local colorize = require('utils').colorize
local stdout = require('utils').stdout
return function(key, value, color)
  stdout:write(key .. ": " .. colorize(color or "highlight", value) .. "\n")
end
