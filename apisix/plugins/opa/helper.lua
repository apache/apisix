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

local core        = require("apisix.core")
local get_service = require("apisix.http.service").get
local ngx_time    = ngx.time

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


local function build_http_route(conf, ctx, remove_upstream)
    local route = core.table.clone(ctx.matched_route).value

    if remove_upstream and route and route.upstream then
        route.upstream = nil
    end

    return route
end


local function _build_http_service(conf, ctx)
    local service_id = ctx.service_id

    -- possible that the route is not bind a service
    if service_id then
        return core.table.clone(get_service(service_id)).value
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
    return core.table.clone(ctx.consumer)
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
