local channel = require 'coro-channel'
local wrapWrite = channel.wrapWrite

require('tap')(function (test)
  test('Writer: finish writing instantly', function ()
    local ssocket = {
      is_closing = function()
        return true
      end
    }

    local success, err
    local write = wrapWrite(ssocket)

    ssocket.write = function(self, chunk, callback)
      callback()
      return true
    end
    success, err = write('succeeds writing')
    assert(success)
    assert(not err) -- if an error message is returned while success is true closer won't be triggered

    ssocket.write = function(self, chunk, callback)
      callback('error message')
      return false, 'error message'
    end
    success, err = write('failed write')
    assert(not success) -- apparently this could be either false or nil
    assert(err == 'error message')
  end)
end)
