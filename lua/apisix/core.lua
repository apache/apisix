local log = require("apisix.core.log")
local local_conf = require("apisix.core.config_local").local_conf()

local config_center = local_conf.apisix and local_conf.apisix.config_center
                      or "etcd"
log.info("use config_center: ", config_center)

return {
    version  = require("apisix.core.version"),
    log      = log,
    config   = require("apisix.core.config_" .. config_center),
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
