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

local base64          = require("ngx.base64")
local ngx_re          = require("ngx.re")

local ngx      = ngx
local tostring = tostring
local tonumber = tonumber

local plugin_name = "skywalking-logger"
local batch_processor_manager = bp_manager_mod.new("skywalking logger")
local schema = {
    type = "object",
    properties = {
        endpoint_addr = core.schema.uri_def,
        service_name = {type = "string", default = "APISIX"},
        service_instance_name = {type = "string", default = "APISIX Instance Name"},
        log_format = {type = "object"},
        timeout = {type = "integer", minimum = 1, default = 3},
        include_req_body = {type = "boolean", default = false},
    },
    required = {"endpoint_addr"},
}


local metadata_schema = {
    type = "object",
    properties = {
        log_format = log_util.metadata_schema_log_format,
    },
}


local _M = {
    version = 0.1,
    priority = 408,
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
    local url_decoded = url.parse(conf.endpoint_addr)
    local host = url_decoded.host
    local port = url_decoded.port

    core.log.info("sending a batch logs to ", conf.endpoint_addr)

    local httpc = http.new()
    httpc:set_timeout(conf.timeout * 1000)
    local ok, err = httpc:connect(host, port)

    if not ok then
        return false, "failed to connect to host[" .. host .. "] port["
            .. tostring(port) .. "] " .. err
    end

    local httpc_res, httpc_err = httpc:request({
        method = "POST",
        path = "/v3/logs",
        body = log_message,
        headers = {
            ["Host"] = url_decoded.host,
            ["Content-Type"] = "application/json",
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


function _M.log(conf, ctx)
    local log_body = log_util.get_log_entry(plugin_name, conf, ctx)
    local trace_context
    local sw_header = ngx.req.get_headers()["sw8"]
    if sw_header then
        -- 1-TRACEID-SEGMENTID-SPANID-PARENT_SERVICE-PARENT_INSTANCE-PARENT_ENDPOINT-IPPORT
        local ids = ngx_re.split(sw_header, '-')
        if #ids == 8 then
            trace_context = {
                traceId = base64.decode_base64url(ids[2]),
                traceSegmentId = base64.decode_base64url(ids[3]),
                spanId = tonumber(ids[4])
            }
        else
            core.log.warn("failed to parse trace_context header: ", sw_header)
        end
    end

    local entry = {
        traceContext = trace_context,
        body = {
            json = {
                json = core.json.encode(log_body, true)
            }
        },
        service = conf.service_name,
        serviceInstance = conf.service_instance_name,
        endpoint = ctx.var.uri,
    }

    if batch_processor_manager:add_entry(conf, entry) then
        return
    end

    -- Generate a function to be executed by the batch processor
    local func = function(entries, batch_max_size)
        local data, err = core.json.encode(entries)
        if not data then
            return false, 'error occurred while encoding the data: ' .. err
        end

        return send_http_data(conf, data)
    end

    batch_processor_manager:add_entry_to_new_processor(conf, entry, ctx, func)
end


return _M
