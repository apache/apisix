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

local ngx      = ngx
local tostring = tostring
local ipairs   = ipairs
local timer_at = ngx.timer.at

local plugin_name = "clickhouse-logger"
local stale_timer_running = false
local buffers = {}

local schema = {
    type = "object",
    properties = {
        endpoint_addr = core.schema.uri_def,
        user = {type = "string", default = ""},
        password = {type = "string", default = ""},
        database = {type = "string", default = ""},
        logtable = {type = "string", default = ""},
        timeout = {type = "integer", minimum = 1, default = 3},
        name = {type = "string", default = "clickhouse logger"},
        max_retry_count = {type = "integer", minimum = 0, default = 0},
        retry_delay = {type = "integer", minimum = 0, default = 1},
        batch_max_size = {type = "integer", minimum = 1, default = 100}
    },
    required = {"endpoint_addr", "user", "password", "database", "logtable"}
}


local metadata_schema = {
    type = "object",
    properties = {
        log_format = log_util.metadata_schema_log_format,
    },
}


local _M = {
    version = 0.1,
    priority = 399,
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

    if ((not port) and url_decoded.scheme == "https") then
        port = 443
    elseif not port then
        port = 80
    end

    local httpc = http.new()
    httpc:set_timeout(conf.timeout * 1000)
    local ok, err = httpc:connect(host, port)

    if not ok then
        return false, "failed to connect to host[" .. host .. "] port["
            .. tostring(port) .. "] " .. err
    end

    if url_decoded.scheme == "https" then
        ok, err = httpc:ssl_handshake(true, host, false)
        if not ok then
            return false, "failed to perform SSL with host[" .. host .. "] "
                .. "port[" .. tostring(port) .. "] " .. err
        end
    end
    url_decoded.query['database'] = conf.database

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
    local metadata = plugin.plugin_metadata("http-logger")
    core.log.info("metadata: ", core.json.delay_encode(metadata))
    local entry

    if metadata and metadata.value.log_format
       and core.table.nkeys(metadata.value.log_format) > 0
    then
        entry = log_util.get_custom_format_log(ctx, metadata.value.log_format)
    else
        entry = log_util.get_full_log(ngx, conf)
    end

    if not entry.route_id then
        entry.route_id = "no-matched"
    end

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
        local data, err

        if batch_max_size == 1 then
            data, err = core.json.encode(entries[1]) -- encode as single {}
        else
            local log_table = {}
            for i = 1, #entries do
                table.insert(log_table, core.json.encode(entries[i]))
            end
            data = table.concat(log_table, " ")  -- assemble multi items as string "{} {}"
        end

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

