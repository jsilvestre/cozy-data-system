fs = require 'fs'
async = require 'async'
multiparty = require 'multiparty'
db = require('../helpers/db_connect_helper').db_connect()
deleteFiles = require('../helpers/utils').deleteFiles
dbHelper = require '../lib/db_remove_helper'

## Actions

# POST /data/:id/binaries
module.exports.add = (req, res, next) ->
    async.waterfall [
        # check the request body size (~ file size)
        (done) ->
            console.log "check size"
            contentLength = req.header 'content-length'
            maxFileSize = require('../config').maxFileSize
            if contentLength > maxFileSize
                error = new Error "The file is too big (>#{maxFileSize}B)"
                error.status = 400
            done error

        # retrieve data from HTTP request
        (callback) ->
            console.log "parse http request"
            form = new multiparty.Form()
            # fields that should be sent with the file
            expectedFields = ['name']
            b = null
            async.parallel [
                (done) ->
                    fields = {}
                    form.on 'field', (name, value) ->
                        fields[name] = value if name in expectedFields
                        if Object.keys(fields).length is expectedFields.length
                            done null, fields

                    #form.on 'close', -> done null, fields

                (done) ->
                    # if the stream has a filename attribute, it's the file
                    # otherwise it's just a field
                    fileStream = null
                    form.on 'part', (part) ->
                        console.log "got part"
                        done null, part if part.filename

            ], (err, results) ->
                [fields, fileStream] = results
                callback err, fields, fileStream

            form.on 'error', callback
            form.parse req # start the parsing

        # check what to do with the file
        (fields, fileStream, done) ->
            console.log "prepare the upload"
            if fileStream?
                name = if fields.name? then fields.name else fileStream.filename
                if req.doc.binary?[name]?
                    db.get req.doc.binary[name].id, (err, binary) ->
                        done err, binary, name, fileStream, req.doc
                else
                    binary = docType: "Binary"
                    db.save binary, (err, binary) ->
                        done err, binary, name, fileStream, req.doc
            else
                error = new Error "No file sent"
                error.status = 400
                done error

        # manages database interaction
        (binary, name, fileStream, doc, done) ->
            console.log "upload"
            fileData =
                name: name
                "content-type": fileStream.headers['content-type']

            # mandatory otherwise the file isn't in the request
            fileStream.path = name

            stream = db.saveAttachment binary, fileData, (err, binDoc) ->
                if err?
                    done new Error err.error
                else
                    bin = id: binDoc.id, rev: binDoc.rev
                    newBin = if doc.binary? then doc.binary else {}

                    newBin[name] = bin
                    db.merge doc._id, binary: newBin, done

            fileStream.pipe stream

    ], (err, results) ->
        if err? then next err
        else
            res.send 201, success: true
            next()

# GET /data/:id/binaries/:name/
module.exports.get = (req, res, next) ->
    name = req.params.name
    if req.doc.binary and req.doc.binary[name]

        stream = db.getAttachment req.doc.binary[name].id, name, (err) ->
            if err and err.error = "not_found"
                err = new Error "not found"
                err.status = 404
                next err
            else if err
                next new Error err.error
            else
                res.send 200

        if req.headers['range']?
            stream.setHeader 'range', req.headers['range']

        stream.pipe res

        res.on 'close', -> stream.abort()
    else
        err = new Error "not found"
        err.status = 404
        next err

# DELETE /data/:id/binaries/:name
module.exports.remove = (req, res, next) ->
    name = req.params.name
    if req.doc.binary and req.doc.binary[name]
        id = req.doc.binary[name].id
        delete req.doc.binary[name]
        if req.doc.binary.length is 0
            delete req.doc.binary
        db.save req.doc, (err) ->
            db.get id, (err, binary) ->
                if binary?
                    dbHelper.remove binary, (err) ->
                        if err? and err.error = "not_found"
                            err = new Error "not found"
                            err.status = 404
                            next err
                        else if err
                            console.log "[Attachment] err: " + JSON.stringify err
                            next new Error err.error
                        else
                            res.send 204, success: true
                            next()
                else
                    err = new Error "not found"
                    err.status = 404
                    next err
    else
        err = new Error "not found"
        err.status = 404
        next err

