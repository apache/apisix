return {
    version  = 0.1,
    log      = require("apisix.core.log"),
    config   = require("apisix.core.config_etcd"),
    json     = require("apisix.core.json"),
    table    = require("apisix.core.table"),
    request  = require("apisix.core.request"),
    response = require("apisix.core.response"),
    lrucache = require("apisix.core.lrucache"),
    schema   = require("apisix.core.schema"),
    ctx      = require("apisix.core.ctx"),
    timer    = require("apisix.core.timer"),
    id       = require("apisix.core.id"),
    utils    = require("apisix.core.utils"),
    etcd     = require("apisix.core.etcd"),
    http     = require("apisix.core.http"),
    consumer = require("apisix.consumer"),
    tablepool= require("tablepool"),
}
