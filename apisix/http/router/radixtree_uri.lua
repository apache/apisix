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
local core = require("apisix.core")
local base_router = require("apisix.http.route")
local get_services = require("apisix.http.service").services
local ar = require("apisix.router")
local event = require("apisix.core.event")
local cached_router_version
local cached_service_version


local _M = {version = 0.2}


    local uri_routes = {}
    local uri_router
function _M.incremental_operate_radixtree(router, routes, with_parameter)
    local op, route, last_route, err
    local cur_tmp, last_tmp
    local router_opts = {
        no_param_match = with_parameter ~= true
    }

    event.push(event.CONST.BUILD_ROUTER, routes)
    for k, v in pairs(ar.sync_tb) do
        op = ar.sync_tb[k]["op"]
        route = ar.sync_tb[k]["cur_route"]
        last_route = ar.sync_tb[k]["last_route"]
        cur_tmp = {}
        last_tmp = {}

        if route and route.value then
            local status = core.table.try_read_attr(route, "value", "status")
            if status and status == 0 then
                goto CONTINUE
            end

            local filter_fun, err
            if route.value.filter_func then
                filter_fun, err = loadstring(
                    "return " .. route.value.filter_func,
                    "router#" .. route.value.id
                )
                if not filter_fun then
                    core.log.error("failed to load filter function: ", err,
                                    " route id", route.value.id)
                    return
                end

                filter_fun = filter_fun()
            end

            cur_tmp = {
                id = route.value.id,
                paths = route.value.uris or route.value.uri,
                methods = route.value.methods,
                priority = route.value.priority,
                hosts = route.value.hosts or route.value.host,
                remote_addrs = route.value.remote_addrs or route.value.remote_addr,
                vars = route.value.vars,
                filter_fun = filter_fun,
                handler = function(api_ctx, match_opts)
                    api_ctx.matched_params = nil
                    api_ctx.matched_route = route
                    api_ctx.curr_req_matched = match_opts.matched
                end
            }
        end

        if last_route and last_route.value then
            last_tmp = {
                id = last_route.value.id,
                paths = last_route.value.uris or last_route.value.uri,
                methods = last_route.value.methods,
                priority = last_route.value.priority,
                hosts = last_route.value.hosts or last_route.value.host,
                remote_addrs = last_route.value.remote_addrs or last_route.value.remote_addr,
                vars = last_route.value.vars
            }
        end

        if op == "update" then
            core.log.notice("update routes watched from etcd into radixtree. ",
                            core.json.delay_encode(route))
            err = router:update_route(last_tmp, cur_tmp, router_opts)
            if err ~= nil then
                core.log.error("update a route into radixtree failed. ",
                                core.json.delay_encode(route), err)
                return
            end
        elseif op == "create" then
            core.log.notice("create routes watched from etcd into radixtree. ",
                            core.json.delay_encode(route))
            err = router:add_route(cur_tmp, router_opts)
            if err ~= nil then
                core.log.error("add routes into radixtree failed. ",
                                core.json.delay_encode(route), err)
                return
            end
        elseif op == "delete" then
            core.log.notice("delete routes watched from etcd into radixtree. ",
                            core.json.delay_encode(last_route))
            err = router:delete_route(last_tmp, router_opts)
            if err ~= nil then
                core.log.error("delete a route into radixtree failed. ",
                                core.json.delay_encode(last_route), err)
                return
            end
        end

        ar.sync_tb[k] = nil
        ::CONTINUE::
    end
end


function _M.match(api_ctx)
    local user_routes = _M.user_routes
    local _, service_version = get_services()
    if not cached_router_version or cached_router_version ~= user_routes.conf_version
        or not cached_service_version or cached_service_version ~= service_version
    then
        if ar.need_create_radixtree then
            uri_router = base_router.create_radixtree_uri_router(user_routes.values,
                                                                 uri_routes, false)
            ar.need_create_radixtree = false
            core.table.clear(ar.sync_tb)
        else
            _M.incremental_operate_radixtree(uri_router,
                                             user_routes.values, false)
        end

        cached_router_version = user_routes.conf_version
        cached_service_version = service_version
    end

    if not uri_router then
        core.log.error("failed to fetch valid `uri` router: ")
        return true
    end

    return _M.matching(api_ctx)
end


function _M.matching(api_ctx)
    core.log.info("route match mode: radixtree_uri")
    return base_router.match_uri(uri_router, api_ctx)
end


return _M
