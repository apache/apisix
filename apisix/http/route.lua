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
local radixtree = require("resty.radixtree")
local router = require("apisix.utils.router")
local core = require("apisix.core")
local expr = require("resty.expr.v1")
local plugin_checker = require("apisix.plugin").plugin_checker
local ipairs = ipairs
local type = type
local error = error
local loadstring = loadstring


local _M = {}


function _M.create_radixtree_uri_router(routes, uri_routes, with_parameter)
    routes = routes or {}

    core.table.clear(uri_routes)

    for _, route in ipairs(routes) do
        if type(route) == "table" then
            local status = core.table.try_read_attr(route, "value", "status")
            -- check the status
            if status and status == 0 then
                goto CONTINUE
            end

            local filter_fun, err
            if route.value.filter_func then
                filter_fun, err = loadstring(
                                        "return " .. route.value.filter_func,
                                        "router#" .. route.value.id)
                if not filter_fun then
                    core.log.error("failed to load filter function: ", err,
                                   " route id: ", route.value.id)
                    goto CONTINUE
                end

                filter_fun = filter_fun()
            end

            core.log.info("insert uri route: ",
                          core.json.delay_encode(route.value, true))
            core.table.insert(uri_routes, {
                paths = route.value.uris or route.value.uri,
                methods = route.value.methods,
                priority = route.value.priority,
                hosts = route.value.hosts or route.value.host,
                remote_addrs = route.value.remote_addrs
                               or route.value.remote_addr,
                vars = route.value.vars,
                filter_fun = filter_fun,
                handler = function (api_ctx, match_opts)
                    api_ctx.matched_params = nil
                    api_ctx.matched_route = route
                    api_ctx.curr_req_matched = match_opts.matched
                end
            })

            ::CONTINUE::
        end
    end

    core.log.info("route items: ", core.json.delay_encode(uri_routes, true))

    if with_parameter then
        return radixtree.new(uri_routes)
    else
        return router.new(uri_routes)
    end
end


function _M.match_uri(uri_router, match_opts, api_ctx)
    core.table.clear(match_opts)
    match_opts.method = api_ctx.var.request_method
    match_opts.host = api_ctx.var.host
    match_opts.remote_addr = api_ctx.var.remote_addr
    match_opts.vars = api_ctx.var
    match_opts.matched = core.tablepool.fetch("matched_route_record", 0, 4)

    local ok = uri_router:dispatch(api_ctx.var.uri, match_opts, api_ctx, match_opts)
    return ok
end


-- additional check for synced route configuration, run after schema check
local function check_route(route)
    local ok, err = plugin_checker(route)
    if not ok then
        return nil, err
    end

    if route.vars then
        ok, err = expr.new(route.vars)
        if not ok then
            return nil, "failed to validate the 'vars' expression: " .. err
        end
    end

    return true
end


function _M.init_worker(filter)
    local user_routes, err = core.config.new("/routes", {
            automatic = true,
            item_schema = core.schema.route,
            checker = check_route,
            filter = filter,
        })
    if not user_routes then
        error("failed to create etcd instance for fetching /routes : " .. err)
    end

    return user_routes
end


return _M
