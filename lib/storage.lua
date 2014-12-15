local config = require('./config')
return require('./storage-' .. config.storage)(config.database)
