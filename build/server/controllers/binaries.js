// Generated by CoffeeScript 1.8.0
var async, db, dbHelper, deleteFiles, downloader, fs, log, multiparty;

fs = require("fs");

multiparty = require('multiparty');

log = require('printit')({
  date: true,
  prefix: 'binaries'
});

db = require('../helpers/db_connect_helper').db_connect();

deleteFiles = require('../helpers/utils').deleteFiles;

dbHelper = require('../lib/db_remove_helper');

downloader = require('../lib/downloader');

async = require('async');

module.exports.add = function(req, res, next) {
  var fields, form, nofile;
  form = new multiparty.Form({
    autoFields: false,
    autoFiles: false
  });
  form.parse(req);
  nofile = true;
  fields = {};
  form.on('part', function(part) {
    var attachBinary, binary, fileData, name, _ref;
    if (part.filename == null) {
      fields[part.name] = '';
      part.on('data', function(buffer) {
        return fields[part.name] = buffer.toString();
      });
      return part.resume();
    } else {
      nofile = false;
      if (fields.name != null) {
        name = fields.name;
      } else {
        name = part.filename;
      }
      fileData = {
        name: name,
        "content-type": part.headers['content-type']
      };
      attachBinary = function(binary) {
        var stream;
        log.info("binary " + name + " ready for storage");
        stream = db.saveAttachment(binary, fileData, function(err, binDoc) {
          var bin, binList;
          if (err) {
            log.error("" + (JSON.stringify(err)));
            return form.emit('error', new Error(err.error));
          } else {
            log.info("Binary " + name + " stored in Couchdb");
            bin = {
              id: binDoc.id,
              rev: binDoc.rev
            };
            if (req.doc.binary) {
              binList = req.doc.binary;
            } else {
              binList = {};
            }
            binList[name] = bin;
            return db.merge(req.doc._id, {
              binary: binList
            }, function(err) {
              return res.send(201, {
                success: true
              });
            });
          }
        });
        return part.pipe(stream);
      };
      if (((_ref = req.doc.binary) != null ? _ref[name] : void 0) != null) {
        return db.get(req.doc.binary[name].id, function(err, binary) {
          return attachBinary(binary);
        });
      } else {
        binary = {
          docType: "Binary"
        };
        return db.save(binary, function(err, binDoc) {
          return attachBinary(binDoc);
        });
      }
    }
  });
  form.on('progress', function(bytesReceived, bytesExpected) {});
  form.on('error', function(err) {
    return next(err);
  });
  return form.on('close', function() {
    if (nofile) {
      res.send(400, {
        error: 'No file sent'
      });
    }
    return next();
  });
};

module.exports.get = function(req, res, next) {
  var binary, err, id, name, stream;
  name = req.params.name;
  binary = req.doc.binary;
  if (binary && binary[name]) {
    id = binary[name].id;
    return stream = downloader.download(id, name, function(err, stream) {
      if (err && err.error === "not_found") {
        err = new Error("not found");
        err.status = 404;
        return next(err);
      } else if (err) {
        return next(new Error(err.error));
      } else {
        res.setHeader('Content-Length', stream.headers['content-length']);
        res.setHeader('Content-Type', stream.headers['content-type']);
        if (req.headers['range'] != null) {
          stream.setHeader('range', req.headers['range']);
        }
        return stream.pipe(res);
      }
    });
  } else {
    err = new Error("not found");
    err.status = 404;
    return next(err);
  }
};

module.exports.remove = function(req, res, next) {
  var err, id, name;
  name = req.params.name;
  if (req.doc.binary && req.doc.binary[name]) {
    id = req.doc.binary[name].id;
    delete req.doc.binary[name];
    if (req.doc.binary.length === 0) {
      delete req.doc.binary;
    }
    return db.save(req.doc, function(err) {
      return db.get(id, function(err, binary) {
        if (binary != null) {
          return dbHelper.remove(binary, function(err) {
            if ((err != null) && (err.error = "not_found")) {
              err = new Error("not found");
              err.status = 404;
              return next(err);
            } else if (err) {
              console.log("[Attachment] err: " + JSON.stringify(err));
              return next(new Error(err.error));
            } else {
              res.send(204, {
                success: true
              });
              return next();
            }
          });
        } else {
          err = new Error("not found");
          err.status = 404;
          return next(err);
        }
      });
    });
  } else {
    err = new Error("no binary ID is provided");
    err.status = 400;
    return next(err);
  }
};

module.exports.convert = function(req, res, next) {
  var binaries, createBinary, id, removeOldAttach;
  binaries = {};
  id = req.doc.id;
  removeOldAttach = (function(_this) {
    return function(attach, binaryId, callback) {
      return db.get(req.doc.id, function(err, doc) {
        if (err != null) {
          return callback(err);
        } else {
          return db.removeAttachment(doc, attach, function(err) {
            if (err != null) {
              return callback(err);
            } else {
              return db.get(binaryId, function(err, doc) {
                if (err != null) {
                  return callback(err);
                } else {
                  return callback(null, doc);
                }
              });
            }
          });
        }
      });
    };
  })(this);
  createBinary = (function(_this) {
    return function(attach, callback) {
      var binary;
      binary = {
        docType: "Binary"
      };
      return db.save(binary, function(err, binDoc) {
        var attachmentData, readStream, writeStream;
        readStream = db.getAttachment(req.doc.id, attach, function(err) {
          if (err != null) {
            return console.log(err);
          }
        });
        attachmentData = {
          name: attach,
          body: ''
        };
        writeStream = db.saveAttachment(binDoc, attachmentData, function(err, res) {
          if (err != null) {
            return callback(err);
          }
          return removeOldAttach(attach, binDoc._id, function(err, doc) {
            if (err != null) {
              return callback(err);
            } else {
              binaries[attach] = {
                id: doc._id,
                rev: doc._rev
              };
              return callback();
            }
          });
        });
        return readStream.pipe(writeStream);
      });
    };
  })(this);
  if (req.doc._attachments != null) {
    return async.eachSeries(Object.keys(req.doc._attachments), createBinary, function(err) {
      if (err != null) {
        return next(err);
      } else {
        return db.get(req.doc.id, function(err, doc) {
          doc.binaries = binaries;
          return db.save(doc, function(err, doc) {
            if (err) {
              return next(err);
            } else {
              res.send(204, {
                success: true
              });
              return next();
            }
          });
        });
      }
    });
  } else {
    res.send(204, {
      success: true
    });
    return next();
  }
};
