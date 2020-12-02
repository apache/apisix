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
local roundrobin = require("resty.roundrobin")
local ipmatcher  = require("resty.ipmatcher")
local expr       = require("resty.expr.v1")
local table_insert = table.insert

local lrucache_rr_obj = core.lrucache.new({
    ttl = 0, count = 512,
})


local match_def = {
    type = "array",
    items = {
        type = "object",
        properties = {
            vars = {
                type = "array",
                items = {
                    type = "array",
                    items = {
                        {
                            type = "string"
                        },
                        {
                            type = "string"
                        }
                    },
                    additionalItems = {
                        anyOf = {
                            {
                                type = "string"
                            },
                            {
                                type = "number"
                            },
                            {
                                type = "boolean"
                            }
                        }
                    },
                    minItems = 0,
                    maxItems = 10
                }
            }
        }
    },
    -- When there is no `match` rule, the default rule passes.
    -- Perform upstream logic of plugin configuration.
    default = {{ vars = {{"server_port", ">", 0}}}}
}

local upstream_def = {
    type = "object",
    additionalProperties = false,
    properties = {
        name = { type = "string" },
        type = {
            type = "string",
            enum = {
                "roundrobin",
                "chash"
            },
            default = "roundrobin"
        },
        nodes = { type = "object" },
        timeout = { type = "object" },
        enable_websocket = { type = "boolean" },
        pass_host = {
            type = "string",
            enum = {
                "pass", "node", "rewrite"
            }
        },
        upstream_host = { type = "string" }
    },
    dependencies = {
        pass_host = {
            anyOf = {
                {
                    properties = {
                        pass_host = { enum = { "rewrite" }}
                    },
                    required = { "upstream_host" }
                },
                {
                    properties = {
                        pass_host = { enum = { "pass", "node" }}
                    },
                }
            }
        }
    }
}

local upstreams_def = {
    type = "array",
    items = {
        type = "object",
        properties = {
            upstream_id = { type = "string" },
            upstream = upstream_def,
            weight = {
                type = "integer",
                default = 1,
                minimum = 0
            }
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
                    match = match_def,
                    upstreams = upstreams_def
                }
            }
        }
    }
}

local plugin_name = "dynamic-upstream"

local _M = {
    version = 0.1,
    priority = 2523,        -- TODO: add a type field, may be a good idea
    name = plugin_name,
    schema = schema
}

function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)

    if not ok then
        return false, err
    end

    return true
end


local function parse_domain(host)
    local ip_info, err = core.utils.dns_parse(host)
    if not ip_info then
        core.log.error("failed to parse domain: ", host, ", error: ",err)
        return nil, err
    end

    core.log.info("parse addr: ", core.json.delay_encode(ip_info))
    core.log.info("host: ", host)
    if not ip_info.address then
        return nil, "failed to parse domain"
    end

    core.log.info("dns resolver domain: ", host, " to ", ip_info.address)
    return ip_info.address
end


local function parse_domain_for_node(node)
    if not ipmatcher.parse_ipv4(node) and not ipmatcher.parse_ipv6(node) then
        local ip, err = parse_domain(node)
        if ip then
            return ip
        end

        if err then
            return nil, err
        end
    end

    return node
end


local function set_upstream_host(upstream_info, ctx)
    local nodes = upstream_info["nodes"]
    local new_nodes = {}
    for addr, weight in pairs(nodes) do
        local node = {}
        local ip, port, host
        host, port = core.utils.parse_addr(addr)
        ip = parse_domain_for_node(host)
        node.host = ip
        node.port = port
        node.weight = weight
        table_insert(new_nodes, node)
        core.log.info("node: ", core.json.delay_encode(node))

        if not core.utils.parse_ipv4(host) and not core.utils.parse_ipv6(host) then
            if upstream_info["pass_host"] == "pass" then    -- TODO: support rewrite method
                ctx.var.upstream_host = ctx.var.host

            elseif upstream_info["pass_host"] == "node" then
                ctx.var.upstream_host = host
            end

            core.log.info("upstream_host: ", ctx.var.upstream_host)
            break
        end
    end

    core.log.info("new_node: ", core.json.delay_encode(new_nodes))

    local up_conf = {
        name = upstream_info["name"],
        type = upstream_info["type"],
        nodes = new_nodes
    }

    local ok, err = upstream.check_schema(up_conf)
    if not ok then
        return 500, err
    end

    local matched_route = ctx.matched_route
    upstream.set(ctx, up_conf.type .. "#route_" .. matched_route.value.id,
                ctx.conf_version, up_conf, matched_route)
    return
end


local function new_rr_obj(upstreams)
    local server_list = {}
    for _, upstream_obj in ipairs(upstreams) do
        if not upstream_obj.upstream then
            -- If the `upstream` object has only the `weight` value, it means that
            -- the `upstream` weight value on the default `route` has been reached.
            --  Need to set an identifier to mark the empty upstream.
            upstream_obj.upstream = "empty_upstream"
        end
        server_list[upstream_obj.upstream] = upstream_obj.weight
    end

    return roundrobin:new(server_list)
end


function _M.access(conf, ctx)
    local upstreams, match_flag
    for _, rule in pairs(conf.rules) do
        match_flag = true
        for _, single_match in pairs(rule.match) do
            local expr, err = expr.new(single_match.vars)
            if err then
                return 500, {"message: expr failed: ", err}
            end

            match_flag = expr:eval()
            if match_flag then
                break
            end
        end

        if match_flag then
            upstreams = rule.upstreams
            break
        end
    end

    core.log.info("match_flag: ", match_flag)

    if not match_flag then
        return
    end

    local rr_up, err = lrucache_rr_obj(upstreams, nil, new_rr_obj, upstreams)
    if not rr_up then
        core.log.error("lrucache_rr_obj faild: ", err)
        return 500
    end

    local upstream = rr_up:find()
    if upstream and upstream ~= "empty_upstream" then
        core.log.info("upstream: ", core.json.encode(upstream))
        return set_upstream_host(upstream, ctx)
    end

    return
end


return _M
