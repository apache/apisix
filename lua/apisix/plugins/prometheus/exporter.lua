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
                                        "HTTP status codes per service in Kong",
                                        {"code", "service"})
end


do
    local tmp_tab = {}

function _M.log(conf, ctx)
    core.table.clear(tmp_tab)
    tmp_tab[1] = ctx.var.status
    tmp_tab[2] = ctx.var.host
    metrics.status:inc(1, tmp_tab)

    core.log.warn("hit prometheuse plugin")
end

end -- do


function _M.collect()
    if not prometheus or not metrics then
        core.log.err("prometheus: plugin is not initialized, please make sure ",
                     " 'prometheus_metrics' shared dict is present in nginx template")
        return 500, { message = "An unexpected error occurred" }
    end

    -- metrics.connections:set(ngx.time(), label_values.active)

    prometheus:collect()
end


function _M.metric_data()
    return prometheus:metric_data()
end


return _M
