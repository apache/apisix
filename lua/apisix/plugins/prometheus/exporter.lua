-- Copyright (C) Yuansheng Wang

local base_prometheus = require("apisix.plugins.prometheus.base_prometheus")
local prometheus = base_prometheus.init("prometheus-metrics", "apisix_")
local core = require("apisix.core")
local ipairs = ipairs
local ngx_capture = ngx.location.capture
local re_gmatch = ngx.re.gmatch


local metrics = {}
local tmp_tab = {}


local _M = {version = 0.1}


function _M.init()
    core.table.clear(metrics)
    -- across all services
    metrics.connections = prometheus:gauge("nginx_http_current_connections",
            "Number of HTTP connections",
            {"state"})

    metrics.etcd_reachable = prometheus:gauge("etcd_reachable",
            "Config server etcd reachable from Apisix, 0 is unreachable")

    -- per service
    metrics.status = prometheus:counter("http_status",
            "HTTP status codes per service in Apisix",
            {"code", "service"})

    metrics.bandwidth = prometheus:counter("bandwidth",
            "Total bandwidth in bytes consumed per service in Apisix",
            {"type", "service"})
end


function _M.log(conf, ctx)
    core.table.clear(tmp_tab)

    local host = ctx.var.host
    core.table.set(tmp_tab, ctx.var.status, host)
    metrics.status:inc(1, tmp_tab)

    tmp_tab[1] = "ingress"
    metrics.bandwidth:inc(ctx.var.request_length, tmp_tab)

    tmp_tab[1] = "egress"
    metrics.bandwidth:inc(ctx.var.bytes_sent, tmp_tab)
end


    local ngx_statu_items = {"active", "accepted", "handled", "total",
                             "reading", "writing", "waiting"}
local function nginx_status()
    local res = ngx_capture("/apisix.com/nginx_status")
    if not res or res.status ~= 200 then
        core.log.error("failed to fetch Nginx status")
        return
    end

    -- Active connections: 2
    -- server accepts handled requests
    --   26 26 84
    -- Reading: 0 Writing: 1 Waiting: 1

    local iterator, err = re_gmatch(res.body, [[(\d+)]], "jmo")
    if not iterator then
        core.log.error("failed to re.gmatch Nginx status: ", err)
        return
    end

    core.table.clear(tmp_tab)
    for _, name in ipairs(ngx_statu_items) do
        local val = iterator()
        if not val then
            break
        end

        tmp_tab[1] = name
        metrics.connections:set(val[0], tmp_tab)
    end
end


function _M.collect()
    if not prometheus or not metrics then
        core.log.err("prometheus: plugin is not initialized, please make sure ",
                     " 'prometheus_metrics' shared dict is present in nginx template")
        return 500, {message = "An unexpected error occurred"}
    end

    -- across all services
    nginx_status()

    -- config server status
    local config = core.config.new()
    local version, err = config:server_version()
    if version then
        metrics.etcd_reachable:set(1)

    else
        metrics.etcd_reachable:set(0)
        core.log.error("prometheus: failed to reach config server while ",
                       "processingmetrics endpoint: ", err)
    end

    prometheus:collect()
end


function _M.metric_data()
    return prometheus:metric_data()
end


return _M
