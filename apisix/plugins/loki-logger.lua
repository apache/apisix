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
local plugin          = require("apisix.plugin")
local http            = require("resty.http")
local new_tab         = require("table.new")

local pairs        = pairs
local ipairs       = ipairs
local tostring     = tostring
local math_random  = math.random
local table_insert = table.insert
local table_sort   = table.sort
local table_concat = table.concat
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
        headers = {
            type = "object",
            patternProperties = {
                [".*"] = {
                    type = "string",
                    minLength = 1,
                },
            },
        },
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
        log_format_extra = {type = "object"},
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
        max_req_body_bytes = {type = "integer", minimum = 1, default = 524288},
        max_resp_body_bytes = {type = "integer", minimum = 1, default = 524288},
    },
    required = {"endpoint_addrs"}
}


local metadata_schema = {
    type = "object",
    properties = {
        log_format = {
            type = "object"
        },
        log_format_extra = {
            type = "object"
        },
        max_pending_entries = {
            type = "integer",
            description = "maximum number of pending entries in the batch processor",
            minimum = 1,
        },
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
    core.utils.check_tls_bool({"ssl_verify"}, conf, plugin_name)

    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return nil, err
    end
    return log_util.check_log_schema(conf)
end


-- build a stable, collision-resistant key for a resolved label set so entries
-- sharing the exact same labels are grouped into a single Loki stream.
local function gen_label_key(labels)
    local keys = {}
    for k in pairs(labels) do
        keys[#keys + 1] = k
    end
    table_sort(keys)

    local parts = new_tab(#keys, 0)
    for i, k in ipairs(keys) do
        parts[i] = k .. "=" .. labels[k]
    end
    -- NUL separator avoids collisions between distinct key/value boundaries
    return table_concat(parts, "\0")
end


local function send_http_data(conf, log)
    local headers = conf.headers or {}
    headers = core.table.clone(headers)
    headers["X-Scope-OrgID"] = conf.tenant_id
    headers["Content-Type"] = "application/json"

    local params = {
        headers = headers,
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


_M.access = log_util.check_and_read_req_body


function _M.body_filter(conf, ctx)
    log_util.collect_body(conf, ctx)
end


function _M.log(conf, ctx)
    local metadata = plugin.plugin_metadata(plugin_name)
    local max_pending_entries = metadata and metadata.value and
                                metadata.value.max_pending_entries or nil
    local entry = log_util.get_log_entry(plugin_name, conf, ctx)

    if not entry.route_id then
        entry.route_id = "no-matched"
    end

    -- insert start time as log time, multiply to nanoseconds
    -- use string concat to circumvent 64bit integers that LuaVM cannot handle
    -- that is, first process the decimal part of the millisecond value
    -- and then add 6 zeros by string concatenation
    entry.loki_log_time = tostring(ngx.req.start_time() * 1000) .. "000000"

    -- resolve possible variables in label values per request and attach the
    -- result to the entry. Clone first so the shared plugin conf is never
    -- mutated, and resolve before the batch-processor early-return so every
    -- entry carries its own labels (e.g. a per-request $service_name).
    local labels = core.table.clone(conf.log_labels)
    for key, value in pairs(labels) do
        local new_val, err, n_resolved = core.utils.resolve_var(value, ctx.var)
        if err then
            core.log.warn("failed to resolve label '", key, "' value '", value, "': ", err)
        elseif n_resolved > 0 then
            labels[key] = new_val
        end
    end
    entry.loki_labels = labels

    if batch_processor_manager:add_entry(conf, entry, max_pending_entries) then
        return
    end

    -- generate a function to be executed by the batch processor
    local func = function(entries)
        -- group entries into Loki streams by their resolved label set so each
        -- request is logged under its own labels instead of a single shared set
        local streams = new_tab(1, 0)
        local stream_by_key = {}

        for _, entry in ipairs(entries) do
            local entry_labels = entry.loki_labels
            local log_time = entry.loki_log_time
            -- remove logger internal fields so they don't leak into the encoded
            -- log line, then restore them: the batch processor reuses the same
            -- entry tables on retry, so they must survive a failed flush
            entry.loki_log_time = nil
            entry.loki_labels = nil
            local line = core.json.encode(entry)
            entry.loki_log_time = log_time
            entry.loki_labels = entry_labels

            local key = gen_label_key(entry_labels)
            local stream = stream_by_key[key]
            if not stream then
                stream = {
                    stream = entry_labels,
                    values = new_tab(1, 0),
                }
                stream_by_key[key] = stream
                table_insert(streams, stream)
            end

            table_insert(stream.values, {
                log_time, line
            })
        end

        -- build loki request data
        local data = {
            streams = streams
        }

        return send_http_data(conf, data)
    end

    batch_processor_manager:add_entry_to_new_processor(conf, entry, ctx, func, max_pending_entries)
end


return _M
