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
local url             = require("net.url")
local math_random     = math.random

local tostring = tostring

local plugin_name = "clickhouse-logger"
local batch_processor_manager = bp_manager_mod.new(plugin_name)

local schema = {
    type = "object",
    properties = {
        -- deprecated, use "endpoint_addrs" instead
        endpoint_addr = core.schema.uri_def,
        endpoint_addrs = {items = core.schema.uri_def, type = "array", minItems = 1},
        user = {type = "string", default = ""},
        password = {type = "string", default = ""},
        database = {type = "string", default = ""},
        logtable = {type = "string", default = ""},
        timeout = {type = "integer", minimum = 1, default = 3},
        name = {type = "string", default = "clickhouse logger"},
        ssl_verify = {type = "boolean", default = true},
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
        }
    },
    oneOf = {
        {required = {"endpoint_addr", "user", "password", "database", "logtable"}},
        {required = {"endpoint_addrs", "user", "password", "database", "logtable"}}
    },
    encrypt_fields = {"password"},
}


local metadata_schema = {
    type = "object",
    properties = {
        log_format = log_util.metadata_schema_log_format,
    },
}


local _M = {
    version = 0.1,
    priority = 398,
    name = plugin_name,
    schema = batch_processor_manager:wrap_schema(schema),
    metadata_schema = metadata_schema,
}


function _M.check_schema(conf, schema_type)
    if schema_type == core.schema.TYPE_METADATA then
        return core.schema.check(metadata_schema, conf)
    end
    return core.schema.check(schema, conf)
end


local function send_http_data(conf, log_message)
    local err_msg
    local res = true
    local selected_endpoint_addr
    if conf.endpoint_addr then
        selected_endpoint_addr = conf.endpoint_addr
    else
        selected_endpoint_addr = conf.endpoint_addrs[math_random(#conf.endpoint_addrs)]
    end
    local url_decoded = url.parse(selected_endpoint_addr)
    local host = url_decoded.host
    local port = url_decoded.port

    core.log.info("sending a batch logs to ", selected_endpoint_addr)

    if not port then
        if url_decoded.scheme == "https" then
            port = 443
        else
            port = 80
        end
    end

    local httpc = http.new()
    httpc:set_timeout(conf.timeout * 1000)
    local ok, err = httpc:connect(host, port)

    if not ok then
        return false, "failed to connect to host[" .. host .. "] port["
            .. tostring(port) .. "] " .. err
    end

    if url_decoded.scheme == "https" then
        ok, err = httpc:ssl_handshake(true, host, conf.ssl_verify)
        if not ok then
            return false, "failed to perform SSL with host[" .. host .. "] "
                .. "port[" .. tostring(port) .. "] " .. err
        end
    end

    local httpc_res, httpc_err = httpc:request({
        method = "POST",
        path = url_decoded.path,
        query = url_decoded.query,
        body = "INSERT INTO " .. conf.logtable .." FORMAT JSONEachRow " .. log_message,
        headers = {
            ["Host"] = url_decoded.host,
            ["Content-Type"] = "application/json",
            ["X-ClickHouse-User"] = conf.user,
            ["X-ClickHouse-Key"] = conf.password,
            ["X-ClickHouse-Database"] = conf.database
        }
    })

    if not httpc_res then
        return false, "error while sending data to [" .. host .. "] port["
            .. tostring(port) .. "] " .. httpc_err
    end

    -- some error occurred in the server
    if httpc_res.status >= 400 then
        res =  false
        err_msg = "server returned status code[" .. httpc_res.status .. "] host["
            .. host .. "] port[" .. tostring(port) .. "] "
            .. "body[" .. httpc_res:read_body() .. "]"
    end

    return res, err_msg
end


function _M.body_filter(conf, ctx)
    log_util.collect_body(conf, ctx)
end


function _M.log(conf, ctx)
    local entry = log_util.get_log_entry(plugin_name, conf, ctx)

    if batch_processor_manager:add_entry(conf, entry) then
        return
    end

    -- Generate a function to be executed by the batch processor
    local func = function(entries, batch_max_size)
        local data, err

        if batch_max_size == 1 then
            data, err = core.json.encode(entries[1]) -- encode as single {}
        else
            local log_table = {}
            for i = 1, #entries do
                core.table.insert(log_table, core.json.encode(entries[i]))
            end
            data = core.table.concat(log_table, " ")  -- assemble multi items as string "{} {}"
        end

        if not data then
            return false, 'error occurred while encoding the data: ' .. err
        end

        return send_http_data(conf, data)
    end

    batch_processor_manager:add_entry_to_new_processor(conf, entry, ctx, func)
end


return _M
