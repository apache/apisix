local core = require("apisix.core")
local exporter = require("apisix.plugins.prometheus.exporter")
local plugin_name = "prometheus"


local schema = {
    type = "object",
    additionalProperties = false,
}


local _M = {
    version = 0.1,
    priority = 500,
    name = plugin_name,
    init = exporter.init,
    log  = exporter.log,
    schema = schema,
}


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

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
