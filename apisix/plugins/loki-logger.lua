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

local bp_manager_mod  = require("apisix.utils.batch-processor-manager")
local log_util        = require("apisix.utils.log-util")
local core            = require("apisix.core")
local http            = require("resty.http")
local new_tab         = require("table.new")

local pairs        = pairs
local ipairs       = ipairs
local tostring     = tostring
local math_random  = math.random
local table_insert = table.insert
local ngx          = ngx
local str_format   = core.string.format

local plugin_name = "loki-logger"
local batch_processor_manager = bp_manager_mod.new("loki logger")

local schema = {
    type = "object",
    properties = {
        -- core configurations
        endpoint_addrs = {
            type = "array",
            minItems = 1,
            items = core.schema.uri_def,
        },
        endpoint_uri = {
            type = "string",
            minLength = 1,
            default = "/loki/api/v1/push"
        },
        tenant_id = {type = "string", default = "fake"},
        log_labels = {
            type = "object",
            patternProperties = {
                [".*"] = {
                    type = "string",
                    minLength = 1,
                },
            },
            default = {
                job = "apisix",
            },
        },

        -- connection layer configurations
        ssl_verify = {type = "boolean", default = false},
        timeout = {
            type = "integer",
            minimum = 1,
            maximum = 60000,
            default = 3000,
            description = "timeout in milliseconds",
        },
        keepalive = {type = "boolean", default = true},
        keepalive_timeout = {
            type = "integer",
            minimum = 1000,
            default = 60000,
            description = "keepalive timeout in milliseconds",
        },
        keepalive_pool = {type = "integer", minimum = 1, default = 5},

        -- logger related configurations
        log_format = {type = "object"},
        include_req_body = {type = "boolean", default = false},
        include_req_body_expr = {
            type = "array",
            minItems = 1,
            items = {
                type = "array"
            }
        },
        include_resp_body = {type = "boolean", default = false},
        include_resp_body_expr = {
            type = "array",
            minItems = 1,
            items = {
                type = "array"
            }
        },
    },
    required = {"endpoint_addrs"}
}


local metadata_schema = {
    type = "object",
    properties = {
        log_format = {
            type = "object"
        }
    },
}


local _M = {
    version = 0.1,
    priority = 414,
    name = plugin_name,
    schema = batch_processor_manager:wrap_schema(schema),
    metadata_schema = metadata_schema,
}


function _M.check_schema(conf, schema_type)
    if schema_type == core.schema.TYPE_METADATA then
        return core.schema.check(metadata_schema, conf)
    end

    local check = {"endpoint_addrs"}
    core.utils.check_https(check, conf, plugin_name)
    core.utils.check_tls_bool({conf.ssl_verify}, {"ssl_verify"}, plugin_name)

    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return nil, err
    end
    return log_util.check_log_schema(conf)
end


local function send_http_data(conf, log)
    local params = {
        headers = {
            ["Content-Type"] = "application/json",
            ["X-Scope-OrgID"] = conf.tenant_id,
        },
        keepalive = conf.keepalive,
        ssl_verify = conf.ssl_verify,
        method = "POST",
        body = core.json.encode(log)
    }

    if conf.keepalive then
        params.keepalive_timeout = conf.keepalive_timeout
        params.keepalive_pool = conf.keepalive_pool
    end

    local httpc, err = http.new()
    if not httpc then
        return false, str_format("create http client error: %s", err)
    end
    httpc:set_timeout(conf.timeout)

    -- select an random endpoint and build URL
    local endpoint_url = conf.endpoint_addrs[math_random(#conf.endpoint_addrs)] .. conf.endpoint_uri
    local res, err = httpc:request_uri(endpoint_url, params)
    if not res then
        return false, err
    end

    if res.status >= 300 then
        return false, str_format("loki server returned status: %d, body: %s",
            res.status, res.body or "")
    end

    return true
end


function _M.body_filter(conf, ctx)
    log_util.collect_body(conf, ctx)
end


function _M.log(conf, ctx)
    local entry = log_util.get_log_entry(plugin_name, conf, ctx)

    if not entry.route_id then
        entry.route_id = "no-matched"
    end

    -- insert start time as log time, multiply to nanoseconds
    -- use string concat to circumvent 64bit integers that LuaVM cannot handle
    -- that is, first process the decimal part of the millisecond value
    -- and then add 6 zeros by string concatenation
    entry.loki_log_time = tostring(ngx.req.start_time() * 1000) .. "000000"

    if batch_processor_manager:add_entry(conf, entry) then
        return
    end

    local labels = conf.log_labels

    -- parsing possible variables in label value
    for key, value in pairs(labels) do
        local new_val, err, n_resolved = core.utils.resolve_var(value, ctx.var)
        if not err and n_resolved > 0 then
            labels[key] = new_val
        end
    end

    -- generate a function to be executed by the batch processor
    local func = function(entries)
        -- build loki request data
        local data = {
            streams = {
                {
                    stream = labels,
                    values = new_tab(1, 0),
                }
            }
        }

        -- add all entries to the batch
        for _, entry in ipairs(entries) do
            local log_time = entry.loki_log_time
            entry.loki_log_time = nil -- clean logger internal field

            table_insert(data.streams[1].values, {
                log_time, core.json.encode(entry)
            })
        end

        return send_http_data(conf, data)
    end

    batch_processor_manager:add_entry_to_new_processor(conf, entry, ctx, func)
end


return _M
