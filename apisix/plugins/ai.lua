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
local apisix          = require("apisix")
local core            = require("apisix.core")
local router          = require("apisix.router")
local event           = require("apisix.core.event")
local load_balancer   = require("apisix.balancer")
local balancer        = require("ngx.balancer")
local ipairs          = ipairs
local pcall           = pcall
local loadstring      = loadstring
local type            = type
local encode_base64   = ngx.encode_base64

local get_cache_key_func
local get_cache_key_func_def_render

local get_cache_key_func_def = [[
return function(ctx)
    local var = ctx.var
    return var.uri
        {% if route_flags["methods"] then %}
        .. "#" .. var.method
        {% end %}
        {% if route_flags["host"] then %}
        .. "#" .. var.host
        {% end %}
end
]]

local route_lrucache = core.lrucache.new({
    -- TODO: we need to set the cache size by count of routes
    -- if we have done this feature, we need to release the origin lrucache
    count = 512
})

local schema = {}

local plugin_name = "ai"

local _M = {
    version = 0.1,
    priority = 22900,
    name = plugin_name,
    schema = schema,
    scope = "global",
}

local orig_router_match
local orig_handle_upstream = apisix.handle_upstream
local orig_balancer_run = load_balancer.run


local function match_route(ctx)
    orig_router_match(ctx)
    return ctx.matched_route or false
end


local function ai_match(ctx)
    local key = get_cache_key_func(ctx)
    core.log.info("route cache key: ", key)
    local ver = router.router_http.user_routes.conf_version
    local route_cache = route_lrucache(key, ver,
                                       match_route, ctx)
    -- if the version has not changed, use the cached route
    if route_cache then
        ctx.matched_route = route_cache
    end
end


local function gen_get_cache_key_func(route_flags)
    if get_cache_key_func_def_render == nil then
        local template = require("resty.template")
        get_cache_key_func_def_render = template.compile(get_cache_key_func_def)
    end

    local str = get_cache_key_func_def_render({route_flags = route_flags})
    local func, err = loadstring(str)
    if func == nil then
        return false, err
    else
        local ok, err_or_function = pcall(func)
        if not ok then
            return false, err_or_function
        end
        get_cache_key_func = err_or_function
    end

    return true
end


local function ai_upstream()
    core.log.info("enable sample upstream")
end


local pool_opt = { pool_size = 320 }
local function ai_balancer_run(route)
    local server = route.value.upstream.nodes[1]
    local ok, err = balancer.set_current_peer(server.host, server.port or 80, pool_opt)
    if not ok then
        core.log.error("failed to set server peer [", server.host, ":",
                       server.port, "] err: ", err)
        return ok, err
    end
    balancer.enable_keepalive(60, 1000)
end

local function routes_analyze(routes)
    -- TODO: need to add a option in config.yaml to enable this feature(default is true)
    local route_flags = core.table.new(0, 5)
    local route_up_flags = core.table.new(0, 8)
    for _, route in ipairs(routes) do
        if type(route) == "table" then
            if route.value.methods then
                route_flags["methods"] = true
            end

            if route.value.host or route.hosts then
                route_flags["host"] = true
            end

            if route.value.vars then
                route_flags["vars"] = true
            end

            if route.value.filter_fun then
                route_flags["filter_fun"] = true
            end

            if route.value.remote_addr or route.remote_addrs then
                route_flags["remote_addr"] = true
            end

            if route.value.service then
                route_flags["service"] = true
            end

            if route.value.enable_websocket then
                route_flags["enable_websocket"] = true
            end

            if route.value.plugins then
                route_flags["plugins"] = true
            end

            if route.value.upstream_id then
                route_flags["upstream_id"] = true
            end

            local upstream = route.value.upstream
            if upstream and upstream.nodes and #upstream.nodes == 1 then
                local node = upstream.nodes[1]
                if not core.utils.parse_ipv4(node.host)
                   and not core.utils.parse_ipv6(node.host) then
                    route_up_flags["has_domain"] = true
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
        end
    end

    if route_flags["vars"] or route_flags["filter_fun"]
         or route_flags["remote_addr"] then
        router.router_http.match = orig_router_match
    else
        core.log.info("use ai plane to match route")
        router.router_http.match = ai_match

        local ok, err = gen_get_cache_key_func(route_flags)
        if not ok then
            core.log.error("generate get_cache_key_func failed:", err)
            router.router_http.match = orig_router_match
        end
    end

    if not route_flags["service"]
            and not route_flags["upstream_id"]
            and not route_flags["enable_websocket"]
            and not route_flags["plugins"]
            and not route_up_flags["has_domain"]
            and route_up_flags["pass_host"]
            and route_up_flags["scheme"]
            and not route_up_flags["checks"]
            and not route_up_flags["retries"]
            and not route_up_flags["timeout"]
            and not route_up_flags["timeout"]
            and not route_up_flags["keepalive"] then
            -- replace the upstream module
        apisix.handle_upstream = ai_upstream
        load_balancer.run = ai_balancer_run
    else
        apisix.handle_upstream = orig_handle_upstream
        load_balancer.run = orig_balancer_run
    end
end


function _M.init()
    event.register(event.CONST.BUILD_ROUTER, routes_analyze)
end


function _M.init_worker()
    orig_router_match = router.router_http.match
end

return _M
