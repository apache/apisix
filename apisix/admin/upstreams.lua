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
local core = require("apisix.core")
local get_routes = require("apisix.router").http_routes
local get_services = require("apisix.http.service").services
local apisix_upstream = require("apisix.upstream")
local resource = require("apisix.admin.resource")
local tostring = tostring
local ipairs = ipairs
local type = type


local function check_conf(id, conf, need_id)
    local ok, err = apisix_upstream.check_upstream_conf(conf)
    if not ok then
        return nil, {error_msg = err}
    end

    return true
end


local function delete_checker(id)
    local routes, routes_ver = get_routes()
    if routes_ver and routes then
        for _, route in ipairs(routes) do
            if type(route) == "table" and route.value
               and route.value.upstream_id
               and tostring(route.value.upstream_id) == id then
                return 400, {error_msg = "can not delete this upstream,"
                                         .. " route [" .. route.value.id
                                         .. "] is still using it now"}
            end
        end
    end

    local services, services_ver = get_services()
    core.log.info("services: ", core.json.delay_encode(services, true))
    core.log.info("services_ver: ", services_ver)
    if services_ver and services then
        for _, service in ipairs(services) do
            if type(service) == "table" and service.value
               and service.value.upstream_id
               and tostring(service.value.upstream_id) == id then
                return 400, {error_msg = "can not delete this upstream,"
                                         .. " service [" .. service.value.id
                                         .. "] is still using it now"}
            end
        end
    end

    return nil, nil
end


return resource.new({
    name = "upstreams",
    kind = "upstream",
    schema = core.schema.upstream,
    checker = check_conf,
    delete_checker = delete_checker
})
