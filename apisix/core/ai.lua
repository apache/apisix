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
local require         = require
local core            = require("apisix.core")
local ipairs          = ipairs
local type            = type

local route_lrucache = core.lrucache.new({
    -- TODO: we need to set the cache size by count of routes
    -- if we have done this feature, we need to release the origin lrucache
    count = 512
})

local _M = {}

local orig_router_match
local router

local function match_route(ctx)
    orig_router_match(ctx)
    return ctx.matched_route or false
end


local function ai_match(ctx)
    -- TODO: we need to generate cache key dynamically
    local key = ctx.var.uri .. "-" .. ctx.var.method .. "-" .. ctx.var.host
    local ver = router.user_routes.conf_version
    local route_cache = route_lrucache(key, ver,
                                       match_route, ctx)
    -- if the version has not changed, use the cached route
    if route_cache then
        ctx.matched_route = route_cache
    end
end


function  _M.routes_analyze(routes)
    -- TODO: we need to add a option in config.yaml to enable this feature(default is true)
    local route_flags = core.table.new(0, 5)
    local route_up_flags = core.table.new(0, 8)
    for _, route in ipairs(routes) do
        if type(route) == "table" then
            if route.value.vars then
                route_flags["vars"] = true
            end

            if route.value.filter_fun then
                route_flags["filter_fun"] = true
            end

            if route.value.remote_addr or route.value.remote_addrs then
                route_flags["remote_addr"] = true
            end

            if route.value.service then
                route_flags["service"] = true
            end

            if route.value.enable_websocket then
                route_flags["enable_websocket"] = true
            end

            local upstream = route.value.upstream

            if upstream and upstream.nodes and #upstream.nodes == 1 then
                local node = upstream.nodes[1]
                if core.utils.parse_ipv4(node.host) or
                 core.utils.parse_ipv6(node.host) then
                    route_up_flags["no_domain"] = true
                end

                if upstream.pass_host == "pass" then
                    route_up_flags["pass_host"] = true
                end

                if upstream.scheme == "http" then
                    route_up_flags["scheme"] = true
                end

                if upstream.checks then
                    route_up_flags["checks"] = true
                end

                if upstream.retries then
                    route_up_flags["retries"] = true
                end

                if upstream.timeout then
                    route_up_flags["timeout"] = true
                end

                if upstream.tls then
                    route_up_flags["tls"] = true
                end

                if upstream.keepalive then
                    route_up_flags["keepalive"] = true
                end
            end

            if not route_flags["service"] and not route_flags["enable_websocket"]
               and route_up_flags["no_domain"] and route_up_flags["pass_host"]
               and route_up_flags["scheme"] and not route_up_flags["checks"]
               and not route_up_flags["retries"] and not route_up_flags["timeout"]
               and not route_up_flags["timeout"] and not route_up_flags["keepalive"] then
                route["_ai_sample_upstream"] = true
            end
        end
    end

    if route_flags["vars"] or route_flags["filter_fun"]
         or route_flags["remote_addr"] then
        router.match = orig_router_match
    else
        core.log.info("use ai plane to match route")
        router.match = ai_match
    end
end


function _M.init_worker(router_http)
    router = router_http
    orig_router_match = router.match
end

return _M
