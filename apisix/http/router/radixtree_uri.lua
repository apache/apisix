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
local ngx_now = ngx.now
local cached_router_version
local cached_service_version
local last_router_rebuild_time


local _M = {version = 0.2}


    local uri_routes = {}
    local uri_router
function _M.match(api_ctx)
    local user_routes = _M.user_routes
    local _, service_version = get_services()
    if not cached_router_version or cached_router_version ~= user_routes.conf_version
        or not cached_service_version or cached_service_version ~= service_version
    then
        local min_interval = _M.router_rebuild_min_interval or 0
        if min_interval > 0 and last_router_rebuild_time then
            local elapsed = ngx_now() - last_router_rebuild_time
            if elapsed < min_interval then
                core.log.info("skip router rebuild, elapsed: ", elapsed,
                              "s, min_interval: ", min_interval, "s")
                goto MATCH
            end
        end

        uri_router = base_router.create_radixtree_uri_router(user_routes.values,
                                                             uri_routes, false)
        cached_router_version = user_routes.conf_version
        cached_service_version = service_version
        last_router_rebuild_time = ngx_now()
    end

    ::MATCH::
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
