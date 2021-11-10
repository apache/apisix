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

local batch_processor = require("apisix.utils.batch-processor")
local log_util        = require("apisix.utils.log-util")
local core            = require("apisix.core")
local http            = require("resty.http")
local url             = require("net.url")
local plugin          = require("apisix.plugin")

local base64          = require("ngx.base64") 
local ngx_re          = require("ngx.re")

local ngx      = ngx
local tostring = tostring 
local ipairs   = ipairs
local timer_at = ngx.timer.at

local plugin_name = "skywalking-logger"
local stale_timer_running = false
local buffers = {}

local schema = {
    type = "object",
    properties = {
        endpoint_addr = core.schema.uri_def,
        service_name = {type = "string", default = "APISIX"},
        service_instance_name = {type = "string", default = "APISIX Instance Name"},
        timeout = {type = "integer", minimum = 1, default = 3},
        name = {type = "string", default = "skywalking logger"},
        max_retry_count = {type = "integer", minimum = 0, default = 0},
        retry_delay = {type = "integer", minimum = 0, default = 1},
        buffer_duration = {type = "integer", minimum = 1, default = 60},
        inactive_timeout = {type = "integer", minimum = 1, default = 5},
        batch_max_size = {type = "integer", minimum = 1, default = 1000},
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
    priority = 410,
    name = plugin_name,
    schema = schema,
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


-- remove stale objects from the memory after timer expires
local function remove_stale_objects(premature)
    if premature then
        return
    end

    for key, batch in ipairs(buffers) do
        if #batch.entry_buffer.entries == 0 and #batch.batch_to_process == 0 then
            core.log.warn("removing batch processor stale object, conf: ",
                          core.json.delay_encode(key))
            buffers[key] = nil
        end
    end

    stale_timer_running = false
end


function _M.log(conf, ctx)
    local metadata = plugin.plugin_metadata(plugin_name)
    core.log.info("metadata: ", core.json.delay_encode(metadata))

    local log_body
    if metadata and metadata.value.log_format
       and core.table.nkeys(metadata.value.log_format) > 0
    then
        log_body = log_util.get_custom_format_log(ctx, metadata.value.log_format)
    else
        log_body = log_util.get_full_log(ngx, conf)
    end

    if not log_body.route_id then
        log_body.route_id = "no-matched"
    end
    
    local h, err = ngx.req.get_headers()
    -- 1-TRACEID-SEGMENTID-3-PARENT_SERVICE-PARENT_INSTANCE-PARENT_ENDPOINT-IPPORT
    local ids = ngx_re.split(h["sw8"], '-')

    local trace_context = {
        traceId = base64.decode_base64url(ids[2]),
        traceSegment = base64.decode_base64url(ids[3]),
        spanId = tonumber(ids[4])
    }

    local entry = {
        traceContext = trace_context,
        body = {
            json = {
                json = core.json.encode(log_body, true)
            }
        },
        service = conf.service_name,
        serviceInstance = conf.service_instance_name,
        endpoint = ngx.var.uri,
    }

    if not stale_timer_running then
        -- run the timer every 30 mins if any log is present
        timer_at(1800, remove_stale_objects)
        stale_timer_running = true
    end

    local log_buffer = buffers[conf]

    if log_buffer then
        log_buffer:push(entry)
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

    local config = {
        name = conf.name,
        retry_delay = conf.retry_delay,
        batch_max_size = conf.batch_max_size,
        max_retry_count = conf.max_retry_count,
        buffer_duration = conf.buffer_duration,
        inactive_timeout = conf.inactive_timeout,
        route_id = ctx.var.route_id,
        server_addr = ctx.var.server_addr,
    }

    local err
    log_buffer, err = batch_processor:new(func, config)

    if not log_buffer then
        core.log.error("error when creating the batch processor: ", err)
        return
    end

    buffers[conf] = log_buffer
    log_buffer:push(entry)
end


return _M
