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
local is_http         = ngx.config.subsystem == "http"
local enable_keepalive = balancer.enable_keepalive and is_http
local ipairs          = ipairs
local pcall           = pcall
local loadstring      = loadstring
local type            = type
local pairs           = pairs

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

local default_keepalive_pool = {}

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


local pool_opt
local function ai_balancer_run(route)
    local server = route.value.upstream.nodes[1]
    if enable_keepalive then
        local ok, err = balancer.set_current_peer(server.host, server.port or 80, pool_opt)
        if not ok then
            core.log.error("failed to set server peer [", server.host, ":",
                           server.port, "] err: ", err)
            return ok, err
        end
        balancer.enable_keepalive(default_keepalive_pool.idle_timeout,
                                  default_keepalive_pool.requests)
    else
        balancer.set_current_peer(server.host, server.port or 80)
    end
end

local function routes_analyze(routes)
    local route_flags = core.table.new(0, 16)
    local route_up_flags = core.table.new(0, 12)
    for _, route in ipairs(routes) do
        if type(route) == "table" then
            for key, value in pairs(route.value) do
                -- collect route flags
                if key == "methods" then
                    route_flags["methods"] = true
                elseif key == "host" or key == "hosts" then
                    route_flags["host"] = true
                elseif key == "vars" then
                    route_flags["vars"] = true
                elseif key == "filter_fun"then
                    route_flags["filter_fun"] = true
                elseif key == "remote_addr" or key == "remote_addrs" then
                    route_flags["remote_addr"] = true
                elseif key == "service" then
                    route_flags["service"] = true
                elseif key == "enable_websocket" then
                    route_flags["enable_websocket"] = true
                elseif key == "plugins" then
                    route_flags["plugins"] = true
                elseif key == "upstream_id" then
                    route_flags["upstream_id"] = true
                elseif key == "service_id" then
                    route_flags["service_id"] = true
                elseif key == "plugin_config_id" then
                    route_flags["plugin_config_id"] = true
                end

                -- collect upstream flags
                if key == "upstream" then
                    if value.nodes and #value.nodes == 1 then
                        for k, v in pairs(value) do
                            if k == "nodes" then
                                if (not core.utils.parse_ipv4(v[1].host)
                                    and not core.utils.parse_ipv6(v[1].host)) then
                                    route_up_flags["has_domain"] = true
                                end
                            elseif k == "pass_host" and v ~= "pass" then
                                route_up_flags["pass_host"] = true
                            elseif k == "scheme" and v ~= "http" then
                                route_up_flags["scheme"] = true
                            elseif k == "checks" then
                                route_up_flags["checks"] = true
                            elseif k == "retries" then
                                route_up_flags["retries"] = true
                            elseif k == "timeout" then
                                route_up_flags["timeout"] = true
                            elseif k == "tls" then
                                route_up_flags["tls"] = true
                            elseif k == "keepalive" then
                                route_up_flags["keepalive"] = true
                            elseif k == "service_name" then
                                route_up_flags["service_name"] = true
                            end
                        end
                    else
                        route_up_flags["more_nodes"] = true
                    end
                end
            end
        end
    end

    if route_flags["vars"] or route_flags["filter_fun"]
         or route_flags["remote_addr"]
         or route_flags["service_id"]
         or route_flags["plugin_config_id"] then
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

    if route_flags["service"]
         or route_flags["service_id"]
         or route_flags["upstream_id"]
         or route_flags["enable_websocket"]
         or route_flags["plugins"]
         or route_up_flags["has_domain"]
         or route_up_flags["pass_host"]
         or route_up_flags["scheme"]
         or route_up_flags["checks"]
         or route_up_flags["retries"]
         or route_up_flags["timeout"]
         or route_up_flags["tls"]
         or route_up_flags["keepalive"]
         or route_up_flags["service_name"]
         or route_up_flags["more_nodes"] then
        apisix.handle_upstream = orig_handle_upstream
        load_balancer.run = orig_balancer_run
    else
        -- replace the upstream module
        apisix.handle_upstream = ai_upstream
        load_balancer.run = ai_balancer_run
    end
end


function _M.init()
    event.register(event.CONST.BUILD_ROUTER, routes_analyze)
    local local_conf = core.config.local_conf()
    local up_keepalive_conf =
                        core.table.try_read_attr(local_conf, "nginx_config",
                                                 "http", "upstream")
    default_keepalive_pool.idle_timeout =
        core.config_util.parse_time_unit(up_keepalive_conf.keepalive_timeout)
    default_keepalive_pool.size = up_keepalive_conf.keepalive
    default_keepalive_pool.requests = up_keepalive_conf.keepalive_requests

    pool_opt = { pool_size = default_keepalive_pool.size }
end


function _M.init_worker()
    orig_router_match = router.router_http.match
end

return _M
