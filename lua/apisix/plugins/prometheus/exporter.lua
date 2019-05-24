-- Copyright (C) Yuansheng Wang

local base_prometheus = require("apisix.plugins.prometheus.base_prometheus")
local prometheus = base_prometheus.init("prometheus_metrics", "apisix_")
local core = require("apisix.core")
local metrics = {}


local _M = {version = 0.1}


function _M.init()
    core.table.clear(metrics)

    -- across all services
    metrics.connections = prometheus:gauge("nginx_http_current_connections",
                                         "Number of HTTP connections",
                                         {"state"})
end


function _M.log(conf, ctx)
    metrics.connections:set(ngx.time(), { "unix time" })
    core.log.warn("hit prometheuse plugin")
end


function _M.collect()
  if not prometheus or not metrics then
    core.log.err("prometheus: plugin is not initialized, please make sure ",
                 " 'prometheus_metrics' shared dict is present in nginx template")
    return 500, { message = "An unexpected error occurred" }
  end

  metrics.connections:set(ngx.time(), { "active" })

  prometheus:collect()
end


function _M.metric_data()
    return prometheus:metric_data()
end


return _M
