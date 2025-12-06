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
local resource = require("apisix.admin.resource")
local stream_route_checker = require("apisix.stream.router.ip_port").stream_route_checker
local tostring = tostring
local ipairs = ipairs
local type = type


local function check_conf(id, conf, need_id, schema, opts)
    opts = opts or {}
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return nil, {error_msg = "invalid configuration: " .. err}
    end

    local upstream_id = conf.upstream_id
    if upstream_id and not opts.skip_references_check then
        local key = "/upstreams/" .. upstream_id
        local res, err = core.etcd.get(key)
        if not res then
            return nil, {error_msg = "failed to fetch upstream info by "
                                     .. "upstream id [" .. upstream_id .. "]: "
                                     .. err}
        end

        if res.status ~= 200 then
            return nil, {error_msg = "failed to fetch upstream info by "
                                     .. "upstream id [" .. upstream_id .. "], "
                                     .. "response code: " .. res.status}
        end
    end

    local service_id = conf.service_id
    if service_id and not opts.skip_references_check then
        local key = "/services/" .. service_id
        local res, err = core.etcd.get(key)
        if not res then
            return nil, {error_msg = "failed to fetch service info by "
                    .. "service id [" .. service_id .. "]: "
                    .. err}
        end

        if res.status ~= 200 then
            return nil, {error_msg = "failed to fetch service info by "
                    .. "service id [" .. service_id .. "], "
                    .. "response code: " .. res.status}
        end
    end

    if conf.protocol and conf.protocol.superior_id and not opts.skip_references_check then
        local superior_id = conf.protocol.superior_id
        local key = "/stream_routes/" .. superior_id
        local res, err = core.etcd.get(key)
        if not res then
            return nil, {error_msg = "failed to fetch stream routes[" .. superior_id .. "]: "
                                     .. err}
        end

        if res.status ~= 200 then
            return nil, {error_msg = "failed to fetch stream routes[" .. superior_id
                                     .. "], response code: " .. res.status}
        end

        local superior_route = res.body.node.value
        if type(superior_route) == "string" then
            superior_route = core.json.decode(superior_route)
        end

        if superior_route and superior_route.protocol
           and superior_route.protocol.name ~= conf.protocol.name then
            return nil, {error_msg = "protocol mismatch: subordinate protocol ["
                                     .. conf.protocol.name .. "] does not match superior protocol ["
                                     .. superior_route.protocol.name .. "]"}
        end
    end

    local ok, err = stream_route_checker(conf, true)
    if not ok then
        return nil, {error_msg = err}
    end

    return true
end


local function delete_checker(id)
    local key = "/stream_routes"
    local res, err = core.etcd.get(key, {prefix = true})
    if not res then
        return nil, {error_msg = "failed to fetch stream routes: " .. err}
    end

    if res.status ~= 200 then
        return nil, {error_msg = "failed to fetch stream routes, response code: " .. res.status}
    end

    local nodes = res.body.list
    if not nodes then
        if res.body.node and res.body.node.nodes then
            nodes = res.body.node.nodes
        end
    end

    if not nodes then
        return true
    end

    for _, item in ipairs(nodes) do
        local route = item.value
        if type(route) == "string" then
            route = core.json.decode(route)
        end

        if route and route.protocol and tostring(route.protocol.superior_id) == id then
            return 400, {error_msg = "can not delete this stream route directly, stream route ["
                                     .. route.id .. "] is still using it as superior_id"}
        end
    end

    return true
end


return resource.new({
    name = "stream_routes",
    kind = "stream route",
    schema = core.schema.stream_route,
    checker = check_conf,
    delete_checker = delete_checker,
    unsupported_methods = { "patch" },
    list_filter_fields = {
        service_id = true,
        upstream_id = true,
    },
})
