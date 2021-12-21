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

local core          = require("apisix.core")
local get_routes    = require("apisix.router").http_routes
local get_upstreams = require("apisix.upstream").upstreams
local get_consumers = require("apisix.consumer").consumers
local get_services  = require("apisix.http.service").services
local ngx_time      = ngx.time
local ipairs        = ipairs

local _M = {}


-- build a table of Nginx variables with some generality
-- between http subsystem and stream subsystem
local function build_var(conf, ctx)
    return {
        server_addr = ctx.var.server_addr,
        server_port = ctx.var.server_port,
        remote_addr = ctx.var.remote_addr,
        remote_port = ctx.var.remote_port,
        timestamp   = ngx_time(),
    }
end


local function build_http_request(conf, ctx)
    return {
        scheme  = core.request.get_scheme(ctx),
        method  = core.request.get_method(ctx),
        host    = core.request.get_host(ctx),
        port    = core.request.get_port(ctx),
        path    = core.request.get_path(ctx),
        headers = core.request.headers(ctx),
        query   = core.request.get_uri_args(ctx),
    }
end


local function _build_http_route(conf, ctx)
    local route_id = ctx.route_id
    local routes = get_routes()

    for _, route in ipairs(routes) do
        if route.value.id == route_id then
            return core.table.deepcopy(route).value
        end
    end

    return nil
end


local function build_http_route(conf, ctx, remove_upstream)
    local route = _build_http_route(conf, ctx)

    if remove_upstream and route and route.upstream then
        route.upstream = nil
    end

    return route
end


local function _build_http_upstream(conf, ctx)
    local route = build_http_route(conf, ctx, false)

    if route then
        if route.upstream then
            return core.table.deepcopy(route.upstream)
        else
            local upstream_id = route.upstream_id
            local upstreams = get_upstreams()

            for _, upstream in ipairs(upstreams) do
                if upstream.value.id == upstream_id then
                    return core.table.deepcopy(upstream).value
                end
            end
        end
    end

    return nil
end


local function build_http_upstream(conf, ctx)
    local upstream = _build_http_upstream(conf, ctx)

    if upstream and upstream.parent then
        upstream.parent = nil
    end

    return upstream
end


local function _build_http_service(conf, ctx)
    local service_id = ctx.service_id

    -- possible that the route is not bind a service
    if service_id then
        local services = get_services()

        for _, service in ipairs(services) do
            if service.value.id == service_id then
                return core.table.deepcopy(service).value
            end
        end
    end

    return nil
end


local function build_http_service(conf, ctx)
    local service = _build_http_service(conf, ctx)

    if service and service.upstream and service.upstream.parent then
        service.upstream.parent = nil
    end

    return service
end


local function build_http_consumer(conf, ctx)
    local consumer_name = ctx.consumer_name

    if consumer_name then
        local consumers = get_consumers()

        for _, consumer in ipairs(consumers) do
            if consumer.value.username == consumer_name then
                return core.table.deepcopy(consumer).value
            end
        end
    end

    return nil
end


function _M.build_opa_input(conf, ctx, subsystem)
    local data = {
        type    = subsystem,
        request = build_http_request(conf, ctx),
        var     = build_var(conf, ctx)
    }

    if conf.with_route then
        data.route = build_http_route(conf, ctx, true)
    end

    if conf.with_upstream then
        data.upstream = build_http_upstream(conf, ctx)
    end

    if conf.with_consumer then
        data.consumer = build_http_consumer(conf, ctx)
    end

    if conf.with_service then
        data.service = build_http_service(conf, ctx)
    end

    return {
        input = data,
    }
end


return _M
