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
local http_route = require("apisix.http.route")
local ipairs = ipairs
local type = type
local error = error
local tab_insert = table.insert
local loadstring = loadstring
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
    if route.value.filter_func then
        filter_fun, err = loadstring(
                                "return " .. route.value.filter_func,
                                "router#" .. route.value.id)
        if not filter_fun then
            core.log.error("failed to load filter function: ", err,
                            " route id: ", route.value.id)
            return
        end

        filter_fun = filter_fun()
    end

    local hosts = route.value.hosts or {route.value.host}

    local radixtree_route = {
        paths = route.value.uris or route.value.uri,
        methods = route.value.methods,
        priority = route.value.priority,
        remote_addrs = route.value.remote_addrs
                       or route.value.remote_addr,
        vars = route.value.vars,
        filter_fun = filter_fun,
        handler = function (api_ctx, match_opts)
            api_ctx.matched_params = nil
            api_ctx.matched_route = route
            api_ctx.curr_req_matched = match_opts.matched
        end
    }

    if #hosts == 0 then
        core.table.insert(only_uri_routes, radixtree_route)
        return
    end

    for i, host in ipairs(hosts) do
        local host_rev = host:reverse()
        if not host_routes[host_rev] then
            host_routes[host_rev] = {radixtree_route}
        else
            tab_insert(host_routes[host_rev], radixtree_route)
        end
    end
end


local function empty_func() end


local function create_radixtree_router(routes)
    local host_routes = {}
    local only_uri_routes = {}
    host_router = nil

    for _, route in ipairs(routes or {}) do
        local status = core.table.try_read_attr(route, "value", "status")
        -- check the status
        if not status or status == 1 then
            push_host_router(route, host_routes, only_uri_routes)
        end
    end

    -- create router: host_router
    local host_router_routes = {}
    for host_rev, routes in pairs(host_routes) do
        local sub_router = router.new(routes)

        core.table.insert(host_router_routes, {
            paths = host_rev,
            filter_fun = function(vars, opts, ...)
                return sub_router:dispatch(vars.uri, opts, ...)
            end,
            handler = empty_func,
        })
    end
    if #host_router_routes > 0 then
        host_router = router.new(host_router_routes)
    end

    -- create router: only_uri_router
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
    match_opts.matched = core.tablepool.fetch("matched_route_record", 0, 4)

    if host_router then
        local host_uri = api_ctx.var.host
        local ok = host_router:dispatch(host_uri:reverse(), match_opts, api_ctx, match_opts)
        if ok then
            return true
        end
    end

    local ok = only_uri_router:dispatch(api_ctx.var.uri, match_opts, api_ctx, match_opts)
    return ok
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
            checker = http_route.check_route,
            filter = filter,
        })
    if not user_routes then
        error("failed to create etcd instance for fetching /routes : " .. err)
    end
end


return _M
