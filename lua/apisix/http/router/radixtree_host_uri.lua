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
local require = require
local router = require("resty.radixtree")
local core = require("apisix.core")
local plugin = require("apisix.plugin")
local ipairs = ipairs
local type = type
local error = error
local tab_insert = table.insert
local loadstring = loadstring
local str_sub = string.sub
local str_find = string.find
local pairs = pairs
local user_routes
local cached_version
local host_router
local only_uri_router


local _M = {version = 0.1}


local function push_host_router(route, host_routes, only_uri_routes)
    if type(route) ~= "table" then
        return
    end

    local filter_fun, err
    local route_val= route.value

    if route_val.filter_func then
        filter_fun, err = loadstring(
                                "return " .. route_val.filter_func,
                                "router#" .. route_val.id)
        if not filter_fun then
            core.log.error("failed to load filter function: ", err,
                            " route id: ", route_val.id)
            return
        end

        filter_fun = filter_fun()
    end

    local paths = route_val.uris or {route_val.uri}
    local routes = {}
    for i, path in ipairs(paths) do
        local matched_uri = path
        if str_find(path, "*", #path, true) then
            matched_uri = str_sub(path, 1, #path - 1)
        end

        core.table.insert(routes, {
            paths = path,
            methods = route_val.methods,
            remote_addrs = route_val.remote_addrs
                        or route_val.remote_addr,
            vars = route_val.vars,
            filter_fun = filter_fun,
            handler = function (api_ctx)
                api_ctx.matched_uri = matched_uri
                core.log.debug("matched_uri: [", matched_uri, "]")

                api_ctx.matched_params = nil
                api_ctx.matched_route = route
            end
        })
    end

    local hosts = route_val.hosts or {route_val.host}

    if #hosts == 0 then
        for i, route in ipairs(routes) do
            tab_insert(only_uri_routes, route)
        end
        return
    end

    for i, host in ipairs(hosts) do
        local host_rev = host:reverse()

        local host_route
        if not host_routes[host_rev] then
            host_route = {}
            host_routes[host_rev] = host_route
        else
            host_route = host_routes[host_rev]
        end

        for i, route in ipairs(routes) do
            tab_insert(host_route, route)
        end
    end
end


local function empty_func() end


local function create_radixtree_router(routes)
    local host_routes = {}
    local only_uri_routes = {}
    host_router = nil

    for _, route in ipairs(routes or {}) do
        push_host_router(route, host_routes, only_uri_routes)
    end

    -- create router: host_router
    local host_router_routes = {}
    for host_rev, routes in pairs(host_routes) do
        local sub_router = router.new(routes)
        local matched_host = host_rev:reverse()
        if str_find(host_rev, "*", #host_rev, true) then
            matched_host = str_sub(matched_host, 2)
        end

        core.table.insert(host_router_routes, {
            paths = host_rev,
            filter_fun = function(vars, opts, api_ctx, ...)
                api_ctx.matched_host = matched_host
                core.log.debug("matched_host: [", matched_host, "]")

                return sub_router:dispatch(vars.uri, opts, api_ctx, ...)
            end,
            handler = empty_func,
        })
    end
    if #host_router_routes > 0 then
        host_router = router.new(host_router_routes)
    end

    -- create router: only_uri_router
    local api_routes = plugin.api_routes()
    core.log.info("api_routes", core.json.delay_encode(api_routes, true))

    for _, api_route in ipairs(api_routes) do
        if type(api_route) == "table" then
            local paths = api_route.uris or {api_route.uri}
            for i, path in ipairs(paths) do
                local matched_uri = path
                if str_find(path, "*", #path, true) then
                    matched_uri = str_sub(path, 1, #path - 1)
                end

                core.table.insert(only_uri_routes, {
                    paths = path,
                    method = api_route.methods,
                    handler = function(api_ctx, ...)
                        api_ctx.matched_uri = matched_uri
                        core.log.debug("matched_uri: [", matched_uri, "]")
                        return api_route.handler(api_ctx, ...)
                    end,
                })
            end
        end
    end

    only_uri_router = router.new(only_uri_routes)
    return true
end


    local match_opts = {}
function _M.match(api_ctx)
    if not cached_version or cached_version ~= user_routes.conf_version then
        create_radixtree_router(user_routes.values)
        cached_version = user_routes.conf_version
    end

    core.table.clear(match_opts)
    match_opts.method = api_ctx.var.request_method
    match_opts.remote_addr = api_ctx.var.remote_addr
    match_opts.vars = api_ctx.var
    match_opts.host = api_ctx.var.host

    if host_router then
        local host_uri = api_ctx.var.host
        local ok = host_router:dispatch(host_uri:reverse(), match_opts, api_ctx)
        if ok then
            return true
        end
    end

    local ok = only_uri_router:dispatch(api_ctx.var.uri, match_opts, api_ctx)
    if ok then
        return true
    end

    core.log.info("not find any matched route")
    return true
end


function _M.routes()
    if not user_routes then
        return nil, nil
    end

    return user_routes.values, user_routes.conf_version
end


function _M.init_worker(filter)
    local err
    user_routes, err = core.config.new("/routes", {
            automatic = true,
            item_schema = core.schema.route,
            filter = filter,
        })
    if not user_routes then
        error("failed to create etcd instance for fetching /routes : " .. err)
    end
end


return _M
