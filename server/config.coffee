americano = require 'americano'
bodyParser = require 'body-parser'

GB = 1024 * 1024 * 1024

config =
    maxFileSize: 2 * GB
    common:
        use: [
            bodyParser()
            americano.methodOverride()
            americano.errorHandler
                dumpExceptions: true
                showStack: true
        ]

    development: [
        americano.logger 'dev'
    ]

    production: [
        americano.logger 'short'
    ]

    plugins: []

module.exports = config