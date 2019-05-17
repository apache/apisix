return {
    version = 0.1,
    log = require("apisix.core.log"),
    config = require("apisix.core.config"),
    config_etcd = require("apisix.core.config_etcd"),
    json = require("cjson.safe"),
    table = {
        new = require("table.new"),
        clear = require("table.clear"),
    },
}
