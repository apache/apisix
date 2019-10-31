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
local user_routes
local cached_version
local only_uri_routes = {}
local only_uri_router
local host_uri_routes = {}
local host_uri_router


local _M = {version = 0.1}


local function add_host_uri_routes(path, host, route)
    core.log.info("add host+uri route, host: ", host, " path: ", path)
    core.table.insert(host_uri_routes, {
        paths = {host .. path},
        methods = route.value.methods,
        remote_addrs = route.value.remote_addrs or route.value.remote_addr,
        vars = route.value.vars,
        handler = function (api_ctx)
            api_ctx.matched_params = nil
            api_ctx.matched_route = route
        end,
    })
end


local function push_radixtree_host_router(route)
    if type(route) ~= "table" then
        return
    end

    local hosts = route.value.hosts or {route.value.host}
    local hosts_wildcard = {}
    local uris = route.value.uris or {route.value.uri}

    local added_count = 0
    for _, host in ipairs(hosts) do
        if host:sub(1, 1) == "*" then
            core.table.insert(hosts_wildcard, host)
        else
            for _, uri in ipairs(uris) do
                add_host_uri_routes(uri, host, route)
            end
            added_count = added_count + 1
        end
    end

    -- 4 cases:
    -- hosts = {}
    -- hosts = {"foo.com"}
    -- hosts = {"*.foo.com", "bar.com"}
    -- hosts = {"*.foo.com", "*.bar.com"}
    if added_count > 0 and added_count == #hosts then
        return
    end

    if #hosts_wildcard == 0 then
        hosts_wildcard = nil
    end

    core.table.insert(only_uri_routes, {
        paths = uris,
        method = route.value.methods,
        hosts = hosts_wildcard,
        remote_addrs = route.value.remote_addrs or route.value.remote_addr,
        vars = route.value.vars,
        handler = function (api_ctx)
            api_ctx.matched_params = nil
            api_ctx.matched_route = route
        end,
    })

    return
end


local function create_radixtree_router(routes)
    core.table.clear(host_uri_routes)
    core.table.clear(only_uri_routes)
    host_uri_router = nil
    only_uri_router = nil

    for _, route in ipairs(routes or {}) do
        push_radixtree_host_router(route)
    end

    -- create router: host_uri_router
    if #host_uri_routes > 0 then
        host_uri_router = router.new(host_uri_routes)
    end

    -- create router: only_uri_router
    local routes = plugin.api_routes()
    core.log.info("routes", core.json.delay_encode(routes, true))

    for _, route in ipairs(routes) do
        if type(route) == "table" then
            core.table.insert(only_uri_routes, {
                paths = route.uris or route.uri,
                handler = route.handler,
                method = route.methods,
            })
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
    match_opts.method = api_ctx.var.method
    match_opts.remote_addr = api_ctx.var.remote_addr
    match_opts.vars = api_ctx.var
    match_opts.host = api_ctx.var.host

    if host_uri_router then
        local host_uri = api_ctx.var.host .. api_ctx.var.uri
        local ok = host_uri_router:dispatch(host_uri, match_opts, api_ctx)
        if ok then
            return true
        end
    end

    local ok = only_uri_router:dispatch(api_ctx.var.uri, match_opts, api_ctx)
    if ok then
        return true
    end

    core.log.info("not find any matched route")
    return core.response.exit(404)
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
