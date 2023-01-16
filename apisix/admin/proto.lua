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
local type = type
local ipairs = ipairs
local core = require("apisix.core")
local resource = require("apisix.admin.resource")
local get_routes = require("apisix.router").http_routes
local get_services = require("apisix.http.service").services
local compile_proto = require("apisix.plugins.grpc-transcode.proto").compile_proto
local tostring = tostring


local function check_conf(id, conf, need_id, schema)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return nil, {error_msg = "invalid configuration: " .. err}
    end

    local ok, err = compile_proto(conf.content)
    if not ok then
        return nil, {error_msg = "invalid content: " .. err}
    end

    return true
end


local function check_proto_used(plugins, deleting, ptype, pid)

    --core.log.info("check_proto_used plugins: ", core.json.delay_encode(plugins, true))
    --core.log.info("check_proto_used deleting: ", deleting)
    --core.log.info("check_proto_used ptype: ", ptype)
    --core.log.info("check_proto_used pid: ", pid)

    if plugins then
        if type(plugins) == "table" and plugins["grpc-transcode"]
           and plugins["grpc-transcode"].proto_id
           and tostring(plugins["grpc-transcode"].proto_id) == deleting then
            return false, {error_msg = "can not delete this proto,"
                                     .. ptype .. " [" .. pid
                                     .. "] is still using it now"}
        end
    end
    return true
end

local function delete_checker(id)
    core.log.info("proto delete: ", id)

    local routes, routes_ver = get_routes()

    core.log.info("routes: ", core.json.delay_encode(routes, true))
    core.log.info("routes_ver: ", routes_ver)

    if routes_ver and routes then
        for _, route in ipairs(routes) do
            core.log.info("proto delete route item: ", core.json.delay_encode(route, true))
            if type(route) == "table" and route.value and route.value.plugins then
                local ret, err = check_proto_used(route.value.plugins, id, "route",route.value.id)
                if not ret then
                    return 400, err
                end
            end
        end
    end
    core.log.info("proto delete route ref check pass: ", id)

    local services, services_ver = get_services()

    core.log.info("services: ", core.json.delay_encode(services, true))
    core.log.info("services_ver: ", services_ver)

    if services_ver and services then
        for _, service in ipairs(services) do
            if type(service) == "table" and service.value and service.value.plugins then
                local ret, err = check_proto_used(service.value.plugins, id,
                                                "service", service.value.id)
                if not ret then
                    return 400, err
                end
            end
        end
    end
    core.log.info("proto delete service ref check pass: ", id)

    return nil, nil
end


return resource.new({
    name = "protos",
    kind = "proto",
    schema = core.schema.proto,
    checker = check_conf,
    unsupported_methods = {"patch"},
    delete_checker = delete_checker
})
