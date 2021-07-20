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
local errlog = require("ngx.errlog")
local batch_processor = require("apisix.utils.batch-processor")
local plugin = require("apisix.plugin")
local timers = require("apisix.timers")
local http = require("resty.http")
local url = require("net.url")
local plugin_name = "error-log-skywalking-logger"
local table = core.table
local schema_def = core.schema
local ngx = ngx
local string = string
local tostring = tostring
local ipairs  = ipairs
local lrucache = core.lrucache.new({
    ttl = 300, count = 32
})


local metadata_schema = {
    type = "object",
    properties = {
        endpoint = schema_def.uri,
        service_name = {type = "string", default = "APISIX"},
        service_instance_name = {type="string", default = "APISIX Service Instance"},
        timeout = {type = "integer", minimum = 1, default = 3},
        keepalive = {type = "integer", minimum = 1, default = 30},
        level = {type = "string", default = "WARN", enum = {"STDERR", "EMERG", "ALERT", "CRIT",
                "ERR", "ERROR", "WARN", "NOTICE", "INFO", "DEBUG"}},
        batch_max_size = {type = "integer", minimum = 0, default = 1000},
        max_retry_count = {type = "integer", minimum = 0, default = 0},
        retry_delay = {type = "integer", minimum = 0, default = 1},
        buffer_duration = {type = "integer", minimum = 1, default = 60},
        inactive_timeout = {type = "integer", minimum = 1, default = 3},
    },
    required = {"endpoint"}
}


local schema = {
    type = "object",
}


local log_level = {
    STDERR =    ngx.STDERR,
    EMERG  =    ngx.EMERG,
    ALERT  =    ngx.ALERT,
    CRIT   =    ngx.CRIT,
    ERR    =    ngx.ERR,
    ERROR  =    ngx.ERR,
    WARN   =    ngx.WARN,
    NOTICE =    ngx.NOTICE,
    INFO   =    ngx.INFO,
    DEBUG  =    ngx.DEBUG
}


local config = {}
local log_buffer


local _M = {
    version = 0.1,
    priority = 1091,
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


local function send_http_data(log_message)
    local err_msg
    local res = true
    local url_decoded = url.parse(config.endpoint)
    local host = url_decoded.host
    local port = url_decoded.port

    core.log.info("sending a batch logs to ", config.endpoint)

    if ((not port) and url_decoded.scheme == "https") then
        port = 443
    elseif not port then
        port = 80
    end

    local httpc = http.new()
    httpc:set_timeout(config.timeout * 1000)
    local ok, err = httpc:connect(host, port)

    if not ok then
        return false, "failed to connect to host[" .. host .. "] port["
            .. tostring(port) .. "] " .. err
    end

    if url_decoded.scheme == "https" then
        ok, err = httpc:ssl_handshake(true, host, false)
        if not ok then
            return nil, "failed to perform SSL with host[" .. host .. "] "
                .. "port[" .. tostring(port) .. "] " .. err
        end
    end

    local entries = {}
    for i = 1, #log_message, 1 do
        local content = {
            service = config.service_name,
            serviceInstance = config.service_instance_name,
            endpoint = "",
            body = {
                text = {
                    text = log_message[i]
                }
           }
        }
        table.insert(entries, content)
    end

    local httpc_res, httpc_err = httpc:request({
        method = "POST",
        path = url_decoded.path,
        query = url_decoded.query,
        body = core.json.encode(entries),
        headers = {
            ["Host"] = url_decoded.host,
            ["Content-Type"] = "application/json",
            ["Authorization"] = config.auth_header
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


local function update_filter(value)
    local level = log_level[string.upper(value.level)]
    local status, err = errlog.set_filter_level(level)
    if not status then
        return nil, "failed to set filter level by ngx.errlog, the error is :" .. err
    else
        core.log.debug("set the filter_level to ", config.level)
    end

    return value
end


local function process()
    local metadata = plugin.plugin_metadata(plugin_name)
    if not (metadata and metadata.value and metadata.modifiedIndex) then
        core.log.info("please set the correct plugin_metadata for ", plugin_name)
        return
    else
        local err
        config, err = lrucache(plugin_name, metadata.modifiedIndex, update_filter, metadata.value)
        if not config then
            core.log.warn("set log filter failed for ", err)
            return
        end

        if config.service_instance_name == "$hostname" then
           config.service_instance_name = core.utils.gethostname()
        end

    end

    local entries = {}
    local logs = errlog.get_logs(9)

    while ( logs and #logs>0 ) do
        for i = 1, #logs, 3 do
            table.insert(entries, logs[i + 2])
        end
        logs = errlog.get_logs(9)
    end

    if #entries == 0 then
        return
    end

    if log_buffer then
        for _, v in ipairs(entries) do
            log_buffer:push(v)
        end
        return
    end

    local config_bat = {
        retry_delay = config.retry_delay,
        batch_max_size = config.batch_max_size,
        max_retry_count = config.max_retry_count,
        buffer_duration = config.buffer_duration,
        inactive_timeout = config.inactive_timeout,
    }

    local err
    log_buffer, err = batch_processor:new(send_http_data, config_bat)

    if not log_buffer then
        core.log.warn("error when creating the batch processor: ", err)
        return
    end

    for _, v in ipairs(entries) do
        log_buffer:push(v)
    end

end


function _M.init()
    timers.register_timer("plugin#error-log-skywalking-logger", process)
end


function _M.destroy()
    timers.unregister_timer("plugin#error-log-skywalking-logger")
end


return _M

