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

    local superior_id = conf.protocol and conf.protocol.superior_id
    if superior_id and not opts.skip_references_check then
        local key = "/stream_routes/" .. superior_id
        local res, err = core.etcd.get(key)
        if not res then
            return nil, {error_msg = "failed to fetch superior stream route info by "
                    .. "superior id [" .. superior_id .. "]: "
                    .. err}
        end

        if res.status ~= 200 then
            return nil, {error_msg = "failed to fetch superior stream route info by "
                    .. "superior id [" .. superior_id .. "], "
                    .. "response code: " .. res.status}
        end

        if res.body and res.body.node and res.body.node.value then
            local superior_route = res.body.node.value

            if not superior_route.protocol or not superior_route.protocol.name then
                return nil, {error_msg = "superior stream route [" .. superior_id .. "] "
                        .. "does not have a valid protocol configuration"}
            end

            if conf.protocol.name ~= superior_route.protocol.name then
                return nil, {error_msg = "protocol name mismatch: subordinate route has protocol "
                        .. "[" .. conf.protocol.name .. "] but superior route "
                        .. "[" .. superior_id .. "] has protocol "
                        .. "[" .. superior_route.protocol.name .. "]"}
            end
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
    local res, err = core.etcd.get(key, true)
    if not res then
        core.log.error("failed to fetch stream routes from etcd: ", err)
        return nil, nil
    end

    if res.status ~= 200 then
        return nil, nil
    end

    if res.body and res.body.list then
        for _, item in ipairs(res.body.list) do
            if item and item.value and item.value.protocol
                and item.value.protocol.superior_id
                and tostring(item.value.protocol.superior_id) == id then
                    return 400, {error_msg = "can not delete this stream route directly, "
                                            .. "subordinate route [" .. item.value.id .. "] "
                                            .. "is still using it now"}
            end
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
