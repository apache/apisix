local exporter = require("apisix.plugins.prometheus.exporter")
local plugin_name = "prometheus"


local _M = {
    version = 0.1,
    priority = 500,
    name = plugin_name,
    init = exporter.init,
    log  = exporter.log,
}


function _M.check_schema(conf)
    return true
end


function _M.api()
    return {
        {
            methods = {"GET"},
            uri = "/apisix/prometheus/metrics",
            handler = exporter.collect
        }
    }
end


-- only for test
-- function _M.access()
--     ngx.say(exporter.metric_data())
-- end


return _M
