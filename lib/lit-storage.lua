local config = require('./lit-config')
return require('./lit-storage-' .. config.storage)(config.database)
