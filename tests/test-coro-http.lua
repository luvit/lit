local http = require 'coro-http'

require('tap')(function (test)

  test("real http request", function ()
    coroutine.wrap(function()
      local res, data = http.request('GET', 'http://luvit.io/')
      assert(res.code == 301)
      local connection = http.getConnection('luvit.io', 80, false)
      assert(connection)
      connection.socket:close()
    end)()
  end)

end)
