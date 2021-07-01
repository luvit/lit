require('weblit-app')

  .bind({
    host = "0.0.0.0",
    port = 8080
  })

  .use(require('weblit-logger'))
  .use(require('weblit-auto-headers'))

  .route({
    method = "GET",
    path = "/",
  }, function (req, res, go)
    res.code = 200
    res.body = "Hello World\n"
  end)

  .start()

require('uv').run()