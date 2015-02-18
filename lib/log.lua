local pp = require('pretty-print')
local colorize = pp.colorize
local stdout = pp.stdout
return function(key, value, color)
  stdout:write(key .. ": " .. (color and colorize(color, value) or value) .. "\n")
end
