load 'application'

Client = require("request-json").JsonClient
checkPermissions = require('./lib/token').checkDocType

if process.env.NODE_ENV is "test"
    client = new Client("http://localhost:9092/")
else
    client = new Client("http://localhost:9102/")


## Before and after methods

# Check if application is authorized to manipulate connectors doocType
before 'permissions', ->
    auth = req.header('authorization')
    checkPermissions auth, body.docType, (err, isAuthenticated, isAuthorized) =>
        if not isAuthenticated
            err = new Error("Application is not authenticated")
            send error: err, 401
        else if not isAuthorized
            err = new Error("Application is not authorized")
            send error: err, 403
        else
            next()


## Actions

# POST /connectors/bank/:name
# Returns data extracted with connector name. Credentials are required.
action 'bank', ->
    if body.login? and body.password?
        path = "connectors/bank/#{params.name}/"
        client.post path, body, (err, res, resBody) ->
            if err
                send 500
            else if not res?
                send 500
            else if res.statusCode != 200
                send resBody, res.statusCode
            else
                send resBody
    else
        send "Credentials are not sent.", 400
