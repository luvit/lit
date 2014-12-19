local fetch = require('./fetch')

-- Given a storage instance, add in the upstream methods

return function (upstream)

  --[[
  upstream.fetch(hash) -> success
  ----------------------------

  Tell the upstream we want it to fetch a hash from us.
  ]]--
  function upstream.fetch(storage, hash)
    return fetch(upstream, storage, hash);
  end


  return upstream
end
