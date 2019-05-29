-- Copyright (C) Yuansheng Wang

local base_prometheus = require("apisix.plugins.prometheus.base_prometheus")
local prometheus = base_prometheus.init("prometheus_metrics", "apisix_")
local core = require("apisix.core")
local metrics = {}


local _M = {version = 0.1}


function _M.init()
    core.table.clear(metrics)
    -- per service
    metrics.status = prometheus:counter("http_status",
                                        "HTTP status codes per service in APIsix",
                                        {"code", "service"})
end


do
    local t = {}

function _M.log(conf, ctx)
    core.table.clear(t)

    core.table.insert_tail(t, ctx.var.status, ctx.var.host)
    metrics.status:inc(1, t)

    core.log.info("hit prometheuse plugin")
end

end -- do


function _M.collect()
    if not prometheus or not metrics then
        core.log.err("prometheus: plugin is not initialized, please make sure ",
                     " 'prometheus_metrics' shared dict is present in nginx template")
        return 500, {message = "An unexpected error occurred"}
    end

    -- metrics.connections:set(ngx.time(), label_values.active)

    prometheus:collect()
end


function _M.metric_data()
    return prometheus:metric_data()
end


return _M
