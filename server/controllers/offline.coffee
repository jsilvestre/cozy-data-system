json = require 'request-json'
request = require 'request'
url = require 'url'

host = 'http://localhost:5984/'

{getPermissions} = require '../lib/token'

filterCreator = (appSlug, doctypes) ->
    doctypesList = doctypes.map (doctype) -> "'#{doctype}'"
    doctypesList = doctypesList.join ','
    return """
    function(doc, req) {
        if(doc._deleted || doc._id == \"_design/#{appSlug}\" ||
          (doc.docType && [#{doctypesList}].indexOf(doc.docType.toLowerCase()) != -1)
        ) {
            return true;
        }
        else {
            return false;
        }
    }
    """

module.exports.index = (req, res, next) ->

    #console.log req.method, req.url
    #console.log req.query
    #console.log req.params
    #console.log req.body
    #console.log req.headers
    authInfo = req.header 'authorization'
    if authInfo?
        authInfo = authInfoInfo.substr 5, authInfo.length - 1
        authInfo = new Buffer(authInfo, 'base64').toString 'ascii'
        [appSlug, password] = authInfo.split ':'
        console.log 'authenticated request', appSlug, password

        permissions = getPermissions()
        appPermissions = permissions[appSlug]
        doctypes = Object.keys appPermissions
        #filterCreator appSlug, doctypes

        # detect if the request is a _change request
        # to add the filter "authorization"
        if req.params?[0] is '_changes'
            req.body.filter = "#{appSlug}/authorization"

    ###
        the client cannot changed the design doc (security issue)
        we also make sure it doesn't send documents of doctype
        it doesn't have the permission to manipulate
    ###
    if req.body? and req.body.docs?
        for doc, index in req.body.docs
            if doc._id is "_design/#{appSlug}" or \
               # check permissions
               not doc.docType? or doc.docType.toLowerCase() not in doctypes
                delete req.body.docs[index]

    # proxies the request
    targetURL = req.url.replace 'couchapi/', ''
    options =
        method: req.method
        headers: req.headers
        uri: url.resolve host, targetURL

    # TODO: adding DS authentication to Couch instead of deleting
    delete options.headers['authorization']

    # restringify the body
    bodyToTransmit = JSON.stringify req.body
    if bodyToTransmit? and bodyToTransmit.length > 0
        options['body'] = bodyToTransmit

    request options, (err, couchRes, body) ->
        console.log "proxied"
        if err? or not couchRes?
            console.log err
            res.send 500, err
        else
            res.set couchRes.headers
            res.statusCode = couchRes.statusCode
            res.send body

