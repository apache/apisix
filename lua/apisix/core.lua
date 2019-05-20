return {
    version = 0.1,
    log = require("apisix.core.log"),
    config = require("apisix.core.config"),
    json = require("cjson.safe"),
    table = {
        new   = require("table.new"),
        clear = require("table.clear"),
        nkeys = require("table.nkeys"),
    },
    resp = require("apisix.core.resp"),
    typeof = require("apisix.core.typeof"),
}
