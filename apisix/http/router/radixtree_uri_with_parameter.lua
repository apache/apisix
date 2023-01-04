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
local cached_router_version
local cached_service_version


local _M = {}


    local uri_routes = {}
    local uri_router
    local match_opts = {}
function _M.match(api_ctx)
    local user_routes = _M.user_routes
    local _, service_version = get_services()
    if not cached_router_version or cached_router_version ~= user_routes.conf_version
        or not cached_service_version or cached_service_version ~= service_version
    then
        uri_router = base_router.create_radixtree_uri_router(user_routes.values,
                                                             uri_routes, true)
        cached_router_version = user_routes.conf_version
        cached_service_version = service_version
    end

    if not uri_router then
        core.log.error("failed to fetch valid `uri_with_parameter` router: ")
        return true
    end

    return _M.matching(api_ctx)
end


function _M.matching(api_ctx)
    core.log.info("route match mode: radixtree_uri_with_parameter")

    return base_router.match_uri(uri_router, match_opts, api_ctx)
end


return _M
