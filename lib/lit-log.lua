local colorize = require('utils').colorize
return function(key, value, color)
  print(key .. ": " .. colorize(color or "highlight", value))
end
