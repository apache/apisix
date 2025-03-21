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
local rr_balancer = require("apisix.balancer.roundrobin")
local plugin = require("apisix.plugin")
local t1k = require "resty.t1k"
local expr = require("resty.expr.v1")

local ngx = ngx
local ngx_now = ngx.now
local string = string
local fmt = string.format
local tostring = tostring
local tonumber = tonumber
local ipairs = ipairs

local plugin_name = "chaitin-waf"

local vars_schema = {
    type = "array",
}

local lrucache = core.lrucache.new({
    ttl = 300, count = 1024
})

local match_schema = {
    type = "array",
    items = {
        type = "object",
        properties = {
            vars = vars_schema
        }
    },
}

local plugin_schema = {
    type = "object",
    properties = {
        mode = {
            type = "string",
            enum = { "off", "monitor", "block", nil },
            default = nil,
        },
        match = match_schema,
        append_waf_resp_header = {
            type = "boolean",
            default = true
        },
        append_waf_debug_header = {
            type = "boolean",
            default = false
        },
        config = {
            type = "object",
            properties = {
                connect_timeout = {
                    type = "integer",
                },
                send_timeout = {
                    type = "integer",
                },
                read_timeout = {
                    type = "integer",
                },
                req_body_size = {
                    type = "integer",
                },
                keepalive_size = {
                    type = "integer",
                },
                keepalive_timeout = {
                    type = "integer",
                },
                real_client_ip = {
                    type = "boolean"
                }
            },
        },
    },
}

local metadata_schema = {
    type = "object",
    properties = {
        mode = {
            type = "string",
            enum = { "off", "monitor", "block", nil },
            default = nil,
        },
        nodes = {
            type = "array",
            items = {
                type = "object",
                properties = {
                    host = {
                        type = "string",
                        pattern = "^\\*?[0-9a-zA-Z-._\\[\\]:/]+$"
                    },
                    port = {
                        type = "integer",
                        minimum = 1,
                        default = 80
                    },
                },
                required = { "host" }
            },
            minItems = 1,
        },
        config = {
            type = "object",
            properties = {
                connect_timeout = {
                    type = "integer",
                    default = 1000 -- milliseconds
                },
                send_timeout = {
                    type = "integer",
                    default = 1000 -- milliseconds
                },
                read_timeout = {
                    type = "integer",
                    default = 1000 -- milliseconds
                },
                req_body_size = {
                    type = "integer",
                    default = 1024 -- milliseconds
                },
                -- maximum concurrent idle connections to
                -- the SafeLine WAF detection service
                keepalive_size = {
                    type = "integer",
                    default = 256
                },
                keepalive_timeout = {
                    type = "integer",
                    default = 60000 -- milliseconds
                },
                real_client_ip = {
                    type = "boolean",
                    default = true
                }
            },
            default = {},
        },
    },
    required = { "nodes" },
}

local _M = {
    version = 0.1,
    priority = 2700,
    name = plugin_name,
    schema = plugin_schema,
    metadata_schema = metadata_schema
}

local global_server_picker

local HEADER_CHAITIN_WAF = "X-APISIX-CHAITIN-WAF"
local HEADER_CHAITIN_WAF_ERROR = "X-APISIX-CHAITIN-WAF-ERROR"
local HEADER_CHAITIN_WAF_TIME = "X-APISIX-CHAITIN-WAF-TIME"
local HEADER_CHAITIN_WAF_STATUS = "X-APISIX-CHAITIN-WAF-STATUS"
local HEADER_CHAITIN_WAF_ACTION = "X-APISIX-CHAITIN-WAF-ACTION"
local HEADER_CHAITIN_WAF_SERVER = "X-APISIX-CHAITIN-WAF-SERVER"
local blocked_message = [[{"code": %s, "success":false, ]] ..
        [["message": "blocked by Chaitin SafeLine Web Application Firewall", "event_id": "%s"}]]
local warning_message = "chaitin-waf monitor mode: request would have been rejected, event_id: "


function _M.check_schema(conf, schema_type)
    if schema_type == core.schema.TYPE_METADATA then
        return core.schema.check(metadata_schema, conf)
    end

    local ok, err = core.schema.check(plugin_schema, conf)

    if not ok then
        return false, err
    end

    if conf.match then
        for _, m in ipairs(conf.match) do
            local ok, err = expr.new(m.vars)
            if not ok then
                return false, "failed to validate the 'vars' expression: " .. err
            end
        end
    end

    return true
end


local function get_healthy_chaitin_server_nodes(metadata, checker)
    local nodes = metadata.nodes
    local new_nodes = core.table.new(0, #nodes)

    for i = 1, #nodes do
        local host, port = nodes[i].host, nodes[i].port
        new_nodes[host .. ":" .. tostring(port)] = 1
    end

    return new_nodes
end


local function get_chaitin_server(metadata, ctx)
    if not global_server_picker or global_server_picker.upstream ~= metadata.value.nodes then
        local up_nodes = get_healthy_chaitin_server_nodes(metadata.value)
        if core.table.nkeys(up_nodes) == 0 then
            return nil, nil, "no healthy nodes"
        end
        core.log.info("chaitin-waf nodes: ", core.json.delay_encode(up_nodes))

        global_server_picker = rr_balancer.new(up_nodes, metadata.value.nodes)
    end

    local server = global_server_picker.get(ctx)
    local host, port, err = core.utils.parse_addr(server)
    if err then
        return nil, nil, err
    end

    return host, port, nil
end


local function check_match(conf, ctx)
    if not conf.match or #conf.match == 0 then
        return true
    end

    for _, match in ipairs(conf.match) do
        local cache_key = tostring(match.vars)

        local exp, err = lrucache(cache_key, nil, function(vars)
            return expr.new(vars)
        end, match.vars)

        if not exp then
            local msg = "failed to create match expression for " ..
                        tostring(match.vars) .. ", err: " .. tostring(err)
            return false, msg
        end

        local matched = exp:eval(ctx.var)
        if matched then
            return true
        end
    end

    return false
end


local function get_conf(conf, metadata)
    local t = {
        mode = "block",
        real_client_ip = true,
    }

    if metadata.config then
        t.connect_timeout = metadata.config.connect_timeout
        t.send_timeout = metadata.config.send_timeout
        t.read_timeout = metadata.config.read_timeout
        t.req_body_size = metadata.config.req_body_size
        t.keepalive_size = metadata.config.keepalive_size
        t.keepalive_timeout = metadata.config.keepalive_timeout
        t.real_client_ip = metadata.config.real_client_ip or t.real_client_ip
    end

    if conf.config then
        t.connect_timeout = conf.config.connect_timeout
        t.send_timeout = conf.config.send_timeout
        t.read_timeout = conf.config.read_timeout
        t.req_body_size = conf.config.req_body_size
        t.keepalive_size = conf.config.keepalive_size
        t.keepalive_timeout = conf.config.keepalive_timeout
        t.real_client_ip = conf.config.real_client_ip or t.real_client_ip
    end

    t.mode = conf.mode or metadata.mode or t.mode

    return t
end


local function do_access(conf, ctx)
    local extra_headers = {}

    local metadata = plugin.plugin_metadata(plugin_name)
    if not core.table.try_read_attr(metadata, "value", "nodes") then
        extra_headers[HEADER_CHAITIN_WAF] = "err"
        extra_headers[HEADER_CHAITIN_WAF_ERROR] = "missing metadata"
        return 500, nil, extra_headers
    end

    local host, port, err = get_chaitin_server(metadata, ctx)
    if err then
        extra_headers[HEADER_CHAITIN_WAF] = "unhealthy"
        extra_headers[HEADER_CHAITIN_WAF_ERROR] = tostring(err)

        return 500, nil, extra_headers
    end

    core.log.info("picked chaitin-waf server: ", host, ":", port)
    local t = get_conf(conf, metadata.value)
    t.host = host
    t.port = port

    extra_headers[HEADER_CHAITIN_WAF_SERVER] = host

    local mode = t.mode or "block"
    if mode == "off" then
        extra_headers[HEADER_CHAITIN_WAF] = "off"
        return nil, nil, extra_headers
    end

    local match, err = check_match(conf, ctx)
    if not match then
        if err then
            extra_headers[HEADER_CHAITIN_WAF] = "err"
            extra_headers[HEADER_CHAITIN_WAF_ERROR] = tostring(err)
            return 500, nil, extra_headers
        else
            extra_headers[HEADER_CHAITIN_WAF] = "no"
            return nil, nil, extra_headers
        end
    end

    if t.real_client_ip then
        t.client_ip = ctx.var.http_x_forwarded_for or ctx.var.remote_addr
    else
        t.client_ip = ctx.var.remote_addr
    end

    local start_time = ngx_now() * 1000
    local ok, err, result = t1k.do_access(t, false)

    extra_headers[HEADER_CHAITIN_WAF_TIME] = ngx_now() * 1000 - start_time

    if not ok then
        extra_headers[HEADER_CHAITIN_WAF] = "waf-err"
        local err_msg = tostring(err)
        if core.string.find(err_msg, "timeout") then
            extra_headers[HEADER_CHAITIN_WAF] = "timeout"
        end
        extra_headers[HEADER_CHAITIN_WAF_ERROR] = tostring(err)

        if mode == "monitor" then
            core.log.warn("chaitin-waf monitor mode: detected waf error - ", err_msg)
            return nil, nil, extra_headers
        end

        return 500, nil, extra_headers
    else
        extra_headers[HEADER_CHAITIN_WAF] = "yes"
        extra_headers[HEADER_CHAITIN_WAF_ACTION] = "pass"
    end

    local code = 200
    extra_headers[HEADER_CHAITIN_WAF_STATUS] = code

    if result and result.status and result.status ~= 200 and result.event_id then
        extra_headers[HEADER_CHAITIN_WAF_STATUS] = result.status
        extra_headers[HEADER_CHAITIN_WAF_ACTION] = "reject"

        if mode == "monitor" then
            core.log.warn(warning_message, result.event_id)
            return nil, nil, extra_headers
        end

        core.log.error("request rejected by chaitin-waf, event_id: " .. result.event_id)

        return tonumber(result.status),
               fmt(blocked_message, result.status, result.event_id) .. "\n",
               extra_headers
    end

    return nil, nil, extra_headers
end


function _M.access(conf, ctx)
    local code, msg, extra_headers = do_access(conf, ctx)

    if not conf.append_waf_debug_header then
        extra_headers[HEADER_CHAITIN_WAF_ERROR] = nil
        extra_headers[HEADER_CHAITIN_WAF_SERVER] = nil
    end

    if conf.append_waf_resp_header then
        core.response.set_header(extra_headers)
    end

    return code, msg
end


function _M.header_filter(conf, ctx)
    t1k.do_header_filter()
end


return _M
