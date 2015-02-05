local pp = require('pretty-print')
local colorize = pp.colorize
local stdout = pp.stdout
return function(key, value, color)
  stdout:write(key .. ": " .. colorize(color or "highlight", value) .. "\n")
end
