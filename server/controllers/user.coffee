db = require('../helpers/db_connect_helper').db_connect()
locker = require '../lib/locker'
keys = require '../lib/encryption'
checkDocType = require('../lib/token').checkDocType

module.exports.permissions_add  = (req, res, next) ->
    checkDocType req.header('authorization'), "User", (err, isAuthenticated, isAuthorized) =>
        next()

module.exports.lockRequest = (req, res, next) ->
    req.lock = "#{req.params.id}"
    locker.runIfUnlock req.lock, ->
        locker.addLock req.lock
        next()

module.exports.unlockRequest = (req, res, next) ->
    locker.removeLock req.lock

module.exports.getDoc = (req, res, next) ->
    db.get params.id, (err, doc) =>
        if err and err.error is "not_found"
            locker.removeLock req.lock
            res.send 404, error: "not found"
        else if err
            console.log "[Get doc] err: " + JSON.stringify err
            locker.removeLock req.lock
            res.send 500, error: err
        else if doc?
            req.doc = doc
            next()
        else
            locker.removeLock req.lock
            res.send 404, error: "not found"

module.exports.permissions = (req, res, next) ->
    checkDocType req.header('authorization'), req.doc.docType, (err, isAuthenticated, isAuthorized) =>
        next()

# POST /user
module.exports.create = (req, res) ->
    delete body._attachments
    if req.params.id
        db.get req.params.id, (err, doc) -> # this GET needed because of cache
            if doc
                res.send 409, error: "The document exists"
            else
                db.save params.id, req.body, (err, response) ->
                    if err
                        res.send 409, error: err.message
                    else
                        res.send 201, _id: response.id
    else
        db.save req.body, (err, response) ->
            if err
                console.log "[Create] err: " + JSON.stringify err
                res.send 500, error: err.message
            else
                res.send 201, _id: response.id

# PUT /user/merge/:id
module.exports.merge = (req, res, next) ->
    # this version don't take care of conflict (erase DB with the sent value)
    delete body._attachments
    db.merge req.params.id, req.body, (err, response) ->
        next()
        if err
            # oops unexpected error !
            console.log "[Merge] err: " + JSON.stringify err
            res.send 500, error: err.message
        else
            res.send 200, success: true