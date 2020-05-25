--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--
local base_prometheus = require("prometheus")
local core      = require("apisix.core")
local ipairs    = ipairs
local ngx       = ngx
local ngx_capture = ngx.location.capture
local re_gmatch = ngx.re.gmatch
local tonumber = tonumber
local select = select
local prometheus

-- Default set of latency buckets, 1ms to 60s:
local DEFAULT_BUCKETS = { 1, 2, 5, 7, 10, 15, 20, 25, 30, 40, 50, 60, 70,
    80, 90, 100, 200, 300, 400, 500, 1000,
    2000, 5000, 10000, 30000, 60000
}

local metrics = {}


    local inner_tab_arr = {}
    local clear_tab = core.table.clear
local function gen_arr(...)
    clear_tab(inner_tab_arr)

    for i = 1, select('#', ...) do
        inner_tab_arr[i] = select(i, ...)
    end

    return inner_tab_arr
end


local _M = {}


function _M.init()
    -- todo: support hot reload, we may need to update the lua-prometheus
    -- library
    if ngx.get_phase() ~= "init" and ngx.get_phase() ~= "init_worker"  then
        return
    end

    core.table.clear(metrics)

    -- across all services
    prometheus = base_prometheus.init("prometheus-metrics", "apisix_")
    metrics.connections = prometheus:gauge("nginx_http_current_connections",
            "Number of HTTP connections",
            {"state"})

    metrics.etcd_reachable = prometheus:gauge("etcd_reachable",
            "Config server etcd reachable from APISIX, 0 is unreachable")

    -- per service
    metrics.status = prometheus:counter("http_status",
            "HTTP status codes per service in APISIX",
            {"code", "route", "service", "node"})

    metrics.latency = prometheus:histogram("http_latency",
        "HTTP request latency per service in APISIX",
        {"type", "service", "node"}, DEFAULT_BUCKETS)

    metrics.overhead = prometheus:histogram("http_overhead",
        "HTTP request overhead per service in APISIX",
        {"type", "service", "node"}, DEFAULT_BUCKETS)

    metrics.bandwidth = prometheus:counter("bandwidth",
            "Total bandwidth in bytes consumed per service in APISIX",
            {"type", "route", "service", "node"})
end


function _M.log(conf, ctx)
    local vars = ctx.var

    local route_id = ""
    local balancer_ip = ctx.balancer_ip or ""
    local service_id

    local matched_route = ctx.matched_route and ctx.matched_route.value
    if matched_route then
        service_id = matched_route.service_id or ""
        route_id = matched_route.id
    else
        service_id = vars.host
    end

    metrics.status:inc(1,
        gen_arr(vars.status, route_id, service_id, balancer_ip))

    local latency = (ngx.now() - ngx.req.start_time()) * 1000
    metrics.latency:observe(latency,
        gen_arr("request", service_id, balancer_ip))

    local overhead = latency
    if ctx.var.upstream_response_time then
        overhead = overhead - tonumber(ctx.var.upstream_response_time)
    end
    metrics.overhead:observe(overhead,
        gen_arr("request", service_id, balancer_ip))

    metrics.bandwidth:inc(vars.request_length,
        gen_arr("ingress", route_id, service_id, balancer_ip))

    metrics.bandwidth:inc(vars.bytes_sent,
        gen_arr("egress", route_id, service_id, balancer_ip))
end


    local ngx_statu_items = {"active", "accepted", "handled", "total",
                             "reading", "writing", "waiting"}
    local label_values = {}
local function nginx_status()
    local res = ngx_capture("/apisix/nginx_status")
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

    for _, name in ipairs(ngx_statu_items) do
        local val = iterator()
        if not val then
            break
        end

        label_values[1] = name
        metrics.connections:set(val[0], label_values)
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
                       "processing metrics endpoint: ", err)
    end

    core.response.set_header("content_type", "text/plain")
    return 200, core.table.concat(prometheus:metric_data())
end


function _M.metric_data()
    return prometheus:metric_data()
end


return _M
