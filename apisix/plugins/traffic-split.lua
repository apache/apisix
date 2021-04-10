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
local core       = require("apisix.core")
local upstream   = require("apisix.upstream")
local schema_def = require("apisix.schema_def")
local init       = require("apisix.init")
local roundrobin = require("resty.roundrobin")
local ipmatcher  = require("resty.ipmatcher")
local expr       = require("resty.expr.v1")
local pairs      = pairs
local ipairs     = ipairs
local type       = type
local table_insert = table.insert

local lrucache = core.lrucache.new({
    ttl = 0, count = 512
})


local vars_schema = {
    type = "array",
}


local match_schema = {
    type = "array",
    items = {
        type = "object",
        properties = {
            vars = vars_schema
        }
    },
}


local upstreams_schema = {
    type = "array",
    items = {
        type = "object",
        properties = {
            upstream_id = schema_def.id_schema,
            upstream = schema_def.upstream,
            weight = {
                description = "used to split traffic between different" ..
                              "upstreams for plugin configuration",
                type = "integer",
                default = 1,
                minimum = 0
            }
        }
    },
    -- When the upstream configuration of the plugin is missing,
    -- the upstream of `route` is used by default.
    default = {
        {
            weight = 1
        }
    },
    minItems = 1,
    maxItems = 20
}


local schema = {
    type = "object",
    properties = {
        rules = {
            type = "array",
            items = {
                type = "object",
                properties = {
                    match = match_schema,
                    weighted_upstreams = upstreams_schema
                },
                additionalProperties = false
            }
        }
    },
    additionalProperties = false
}

local plugin_name = "traffic-split"

local _M = {
    version = 0.1,
    priority = 966,
    name = plugin_name,
    schema = schema
}

function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)

    if not ok then
        return false, err
    end

    if conf.rules then
        for _, rule in ipairs(conf.rules) do
            if rule.match then
                for _, m in ipairs(rule.match) do
                    local ok, err = expr.new(m.vars)
                    if not ok then
                        return false, "failed to validate the 'vars' expression: " .. err
                    end
                end
            end
        end
    end

    return true
end


local function parse_domain_for_node(node)
    if not ipmatcher.parse_ipv4(node)
       and not ipmatcher.parse_ipv6(node)
    then
        local ip, err = init.parse_domain(node)
        if ip then
            return ip
        end

        if err then
            return nil, err
        end
    end

    return node
end


local function set_pass_host(ctx, upstream_info, host)
    local pass_host = upstream_info.pass_host or "pass"
    if pass_host == "pass" then
        return
    end

    if pass_host == "rewrite" then
        ctx.var.upstream_host = upstream_info.upstream_host
        return
    end

    -- only support single node for `node` mode currently
    ctx.var.upstream_host = host
end


local function set_upstream(upstream_info, ctx)
    local nodes = upstream_info.nodes
    local new_nodes = {}
    if core.table.isarray(nodes) then
        for _, node in ipairs(nodes) do
            set_pass_host(ctx, upstream_info, node.host)
            node.host = parse_domain_for_node(node.host)
            node.port = node.port
            node.weight = node.weight
            table_insert(new_nodes, node)
        end
    else
        for addr, weight in pairs(nodes) do
            local node = {}
            local ip, port, host
            host, port = core.utils.parse_addr(addr)
            set_pass_host(ctx, upstream_info, host)
            ip = parse_domain_for_node(host)
            node.host = ip
            node.port = port
            node.weight = weight
            table_insert(new_nodes, node)
        end
    end
    core.log.info("upstream_host: ", ctx.var.upstream_host)

    local up_conf = {
        name = upstream_info.name,
        type = upstream_info.type,
        hash_on = upstream_info.hash_on,
        key = upstream_info.key,
        nodes = new_nodes,
        timeout = {
            send = upstream_info.timeout and upstream_info.timeout.send or 15,
            read = upstream_info.timeout and upstream_info.timeout.read or 15,
            connect = upstream_info.timeout and upstream_info.timeout.connect or 15
        }
    }

    local ok, err = upstream.check_schema(up_conf)
    if not ok then
        core.log.error("failed to validate generated upstream: ", err)
        return 500, err
    end

    local matched_route = ctx.matched_route
    up_conf.parent = matched_route
    local upstream_key = up_conf.type .. "#route_" ..
                         matched_route.value.id .. "_" ..upstream_info.vid
    core.log.info("upstream_key: ", upstream_key)
    upstream.set(ctx, upstream_key, ctx.conf_version, up_conf)

    return
end


local function new_rr_obj(weighted_upstreams)
    local server_list = {}
    for i, upstream_obj in ipairs(weighted_upstreams) do
        if upstream_obj.upstream_id then
            server_list[upstream_obj.upstream_id] = upstream_obj.weight
        elseif upstream_obj.upstream then
            -- Add a virtual id field to uniquely identify the upstream key.
            upstream_obj.upstream.vid = i
            server_list[upstream_obj.upstream] = upstream_obj.weight
        else
            -- If the upstream object has only the weight value, it means
            -- that the upstream weight value on the default route has been reached.
            -- Mark empty upstream services in the plugin.
            upstream_obj.upstream = "plugin#upstream#is#empty"
            server_list[upstream_obj.upstream] = upstream_obj.weight

        end
    end

    return roundrobin:new(server_list)
end


function _M.access(conf, ctx)
    if not conf or not conf.rules then
        return
    end

    local weighted_upstreams
    local match_passed = true

    for _, rule in ipairs(conf.rules) do
        if not rule.match then
            weighted_upstreams = rule.weighted_upstreams
            break
        end

        for _, single_match in ipairs(rule.match) do
            local expr, err = expr.new(single_match.vars)
            if err then
                core.log.error("vars expression does not match: ", err)
                return 500, err
            end

            match_passed = expr:eval(ctx.var)
            if match_passed then
                break
            end
        end

        if match_passed then
            weighted_upstreams = rule.weighted_upstreams
            break
        end
    end

    core.log.info("match_passed: ", match_passed)

    if not match_passed then
        return
    end

    local rr_up, err = core.lrucache.plugin_ctx(lrucache, ctx, nil, new_rr_obj,
                                                weighted_upstreams)
    if not rr_up then
        core.log.error("lrucache roundrobin failed: ", err)
        return 500
    end

    local upstream = rr_up:find()
    if upstream and type(upstream) == "table" then
        core.log.info("upstream: ", core.json.encode(upstream))
        return set_upstream(upstream, ctx)
    elseif upstream and upstream ~= "plugin#upstream#is#empty" then
        ctx.upstream_id = upstream
        core.log.info("upstream_id: ", upstream)
        return
    end

    ctx.upstream_id = nil
    core.log.info("route_up: ", upstream)
    return
end


return _M
