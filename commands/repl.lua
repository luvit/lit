local prompt = require('prompt')

coroutine.wrap(function ()
  -- prompt returns false on Control+C
  -- and nil on Control+D, assert will catch those and exit the process.
  local name = assert(prompt("Who are you? "))
  local age = tonumber(assert(prompt("How old are you? ")))
  p{name=name,age=age}
end)()
