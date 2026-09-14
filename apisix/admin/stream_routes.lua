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
local apisix_upstream = require("apisix.upstream")
local stream_route_checker = require("apisix.stream.router.ip_port").stream_route_checker
local tostring = tostring
local ipairs = ipairs
local type = type


-- etcd hands a resource back either already decoded or as the raw JSON text.
-- A decode failure and a JSON `null` both have to be rejected here: `null`
-- decodes to the truthy `core.json.null` userdata, which blows up on the first
-- field access instead of failing validation.
local function decode_value(kind, id, value)
    if type(value) == "table" then
        return value
    end

    if type(value) ~= "string" then
        return nil, {error_msg = "failed to read " .. kind .. " [" .. id .. "]: "
                                 .. "unexpected value type " .. type(value)}
    end

    local decoded, decode_err = core.json.decode(value)
    if type(decoded) ~= "table" then
        return nil, {error_msg = "failed to decode " .. kind .. " [" .. id .. "]: "
                                 .. (decode_err or "not an object")}
    end

    return decoded
end


-- Slow start only ramps HTTP upstreams, so an upstream a stream route can reach
-- may not enable it. The route reaches one directly through `upstream_id`, or
-- through a service that embeds one or names one of its own.
local function check_upstream_reference(upstream_id, via)
    local key = "/upstreams/" .. upstream_id
    local res, err = core.etcd.get(key)
    if not res then
        return nil, {error_msg = "failed to fetch upstream info by "
                                 .. "upstream id [" .. upstream_id .. "]: " .. err}
    end

    if res.status ~= 200 then
        return nil, {error_msg = "failed to fetch upstream info by "
                                 .. "upstream id [" .. upstream_id .. "], "
                                 .. "response code: " .. res.status}
    end

    local upstream, decode_err = decode_value("upstream", upstream_id,
                                              res.body.node and res.body.node.value)
    if not upstream then
        return nil, decode_err
    end

    if upstream.warm_up_conf then
        return nil, {error_msg = (via or ("upstream [" .. upstream_id .. "]"))
                                 .. " uses warm_up_conf, which is not supported by "
                                 .. "a stream route"}
    end

    return true
end


local function check_conf(id, conf, need_id, schema, opts)
    opts = opts or {}
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return nil, {error_msg = "invalid configuration: " .. err}
    end

    -- slow start only ramps HTTP upstreams, so a stream route may neither carry
    -- nor point at an upstream that asks for it
    if conf.upstream and conf.upstream.warm_up_conf then
        return nil, {error_msg = "warm_up_conf is not supported by a stream route"}
    end

    local upstream_id = conf.upstream_id
    if upstream_id and not opts.skip_references_check then
        local ok, err = check_upstream_reference(upstream_id)
        if not ok then
            return nil, err
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

        -- a service reaches the same upstream, so it can carry warm_up_conf onto
        -- the L4 path the same way a directly referenced upstream would. The
        -- route only falls back to the service's upstream when it names none of
        -- its own, which is what `merge_service_stream_route` does at runtime
        local service, decode_err = decode_value("service", service_id,
                                                 res.body.node and res.body.node.value)
        if not service then
            return nil, decode_err
        end

        if not upstream_id then
            if service.upstream and service.upstream.warm_up_conf then
                return nil, {error_msg = "service [" .. service_id .. "] uses an "
                                         .. "upstream with warm_up_conf, which is not "
                                         .. "supported by a stream route"}
            end

            if service.upstream_id then
                local ok, err = check_upstream_reference(service.upstream_id,
                                                         "service [" .. service_id
                                                         .. "] upstream ["
                                                         .. service.upstream_id .. "]")
                if not ok then
                    return nil, err
                end
            end
        end
    end

    -- the self-reference check needs no lookup, so it stays outside the gate;
    -- only the etcd fetch below is skipped for standalone validation
    if conf.protocol and conf.protocol.superior_id then
        local superior_id = conf.protocol.superior_id
        if id and tostring(superior_id) == tostring(id) then
            return nil, {error_msg = "stream route can not set itself as superior_id"}
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

        local superior_route, decode_err = decode_value("stream route", superior_id,
                                                        res.body.node and res.body.node.value)
        if not superior_route then
            return nil, decode_err
        end

        if superior_route.protocol
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
        return 503, {error_msg = "failed to fetch stream routes: " .. err}
    end

    if res.status ~= 200 then
        return 503, {error_msg = "failed to fetch stream routes, response code: " .. res.status}
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
            local decoded, decode_err = core.json.decode(route)
            if not decoded then
                return 503, {error_msg = "failed to decode stream route [" .. tostring(item.key)
                                         .. "]: " .. decode_err}
            end
            route = decoded
        end

        if route and route.protocol and tostring(route.protocol.superior_id) == id then
            return 400, {error_msg = "can not delete this stream route directly, stream route ["
                                     .. route.id .. "] is still using it as superior_id"}
        end
    end

    return true
end


local function encrypt_conf(id, conf)
    apisix_upstream.encrypt_conf(conf.upstream)
end


return resource.new({
    name = "stream_routes",
    kind = "stream route",
    schema = core.schema.stream_route,
    checker = check_conf,
    delete_checker = delete_checker,
    encrypt_conf = encrypt_conf,
    unsupported_methods = { "patch" },
    list_filter_fields = {
        service_id = true,
        upstream_id = true,
    },
})
