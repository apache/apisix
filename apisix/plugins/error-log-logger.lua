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
local plugin_name = "error-log-logger"
local errlog = require "ngx.errlog"
local batch_processor = require("apisix.utils.batch-processor")
local table = core.table
local ngx = ngx
local tcp = ngx.socket.tcp
local select = select
local type = type
local string = string
local tostring = tostring
local buffers
local timer
local schema = {
    type = "object",
    properties = {
        host = {type = "string"},
        port = {type = "integer", minimum = 0},
        tls = {type = "boolean", default = false},
        tls_options = {type = "string"},
        timeout = {type = "integer", minimum = 1, default= 3},
        keepalive = {type = "integer", minimum = 1, default= 30},
        name = {type = "string", default = "tcp logger"},
        level = {type = "string", default = "WARN"},
        max_retry_count = {type = "integer", minimum = 0, default = 0},
        retry_delay = {type = "integer", minimum = 0, default = 1},
        buffer_duration = {type = "integer", minimum = 1, default = 60},
        inactive_timeout = {type = "integer", minimum = 1, default = 5},
    },
    additionalProperties = false,
}

local log_level = {
    STDERR =    ngx.STDERR,
    EMERG  =    ngx.EMERG,
    ALERT  =    ngx.ALERT,
    CRIT   =    ngx.CRIT,
    ERR    =    ngx.ERR,
    ERROR  =    ngx.ERR,
    WARN   =    ngx.WARN,
    NOTICE =     ngx.NOTICE,
    INFO   =    ngx.INFO,
    DEBUG  =    ngx.DEBUG
}

local config = {
    name = plugin_name,
    timeout = 3,
    keepalive = 30,
    level = "WARN",
    tls = false,
    retry_delay = 1,
    batch_max_size = 1000,
    max_retry_count = 0,
    buffer_duration = 60,
    inactive_timeout = 5,
}
local _M = {
    version = 0.1,
    priority = 1091,
    name = plugin_name,
    schema = schema,
}


function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end


local function try_attr(t, ...)
    local count = select('#', ...)
    for i = 1, count do
        local attr = select(i, ...)
        t = t[attr]
        if type(t) ~= "table" then
            return false
        end
    end

    return true
end

local function load_attr()
    local local_conf = core.config.local_conf()
    if try_attr(local_conf, "plugin_attr", plugin_name) then
        local attr = local_conf.plugin_attr[plugin_name]
        config.host = attr.host
        config.port = attr.port
        config.level = attr.level or config.level
        config.timeout = attr.timeout or config.timeout
        config.keepalive = attr.keepalive or config.keepalive
        config.tls = attr.tls or config.tls
        config.tls_options = attr.tls_options
        config.retry_delay = attr.retry_delay or config.retry_delay
        config.batch_max_size = attr.batch_max_size or config.batch_max_size
        config.max_retry_count = attr.max_retry_count or config.max_retry_count
        config.buffer_duration = attr.buffer_duration or config.buffer_duration
        config.inactive_timeout = attr.inactive_timeout or config.inactive_timeout
    end
end

local function send_to_server(data)
    local res = false
    local err_msg
    local sock, soc_err = tcp()

    if not sock then
        err_msg = "failed to init the socket " .. soc_err
        return res, err_msg
    end

    sock:settimeout(config.timeout*1000)

    local ok, err = sock:connect(config.host, config.port)
    if not ok then
        err_msg = "failed to connect the TCP server: host[" .. config.host
                  .. "] port[" .. tostring(config.port) .. "] err: " .. err
        return res, err_msg
    end

    if config.tls then
        ok, err = sock:sslhandshake(true, config.tls_options, false)
        if not ok then
            return false, "failed to to perform TLS handshake to TCP server: host["
                          .. config.host .. "] port[" .. tostring(config.port) .. "] err: " .. err
        end
    end

    local bytes, err = sock:send(data)
    if not bytes then
        sock:close()
        err_msg = "failed to send data to TCP server: host[" .. config.host
                  .. "] port[" .. tostring(config.port) .. "] err: " .. err
        return res, err_msg
    end

    sock:setkeepalive(config.keepalive * 1000)
    return true
end

local function process()
    local entries = {}
    local logs = errlog.get_logs(10)
    while ( logs and #logs>0 ) do
        for i = 1, #logs, 3 do
            table.insert(entries, logs[i + 2])
        end
        logs = errlog.get_logs(10)
    end
    if #entries == 0 then
        return
    end
    local log_buffer = buffers[config.id]
    if log_buffer then
        for i = 1, #entries do
            log_buffer:push(entries[i])
        end
        return
    end
    -- Generate a function to be executed by the batch processor
    local func = function(entries)
        return send_to_server(entries)
    end
    local config_bat = {
        name = config.name,
        retry_delay = config.retry_delay,
        batch_max_size = config.batch_max_size,
        max_retry_count = config.max_retry_count,
        buffer_duration = config.buffer_duration,
        inactive_timeout = config.inactive_timeout,
    }

    local err
    log_buffer, err = batch_processor:new(func, config_bat)

    if not log_buffer then
        core.log.error("error when creating the batch processor: ", err)
        return
    end
    buffers[config.id] = log_buffer
    for i = 1, #entries do
        log_buffer:push(entries[i])
    end

end
function _M.init()
    if ngx.get_phase() ~= "init" and ngx.get_phase() ~= "init_worker"  then
        return
    end
    buffers = {}
    config.id = ngx.worker.id()
    load_attr(config)
    if not (config.host and config.port) then
        core.log.warn("please set the host and port of server when enable the error-log-logger.")
        return
    end
    local level = log_level[string.upper(config.level)]
    local status, err = errlog.set_filter_level(level)
    if not status then
        core.log.warn("failed to set filter level by ngx.errlog, the error is :", err)
        return
    end

    if timer then
        return
    end
    local err
    timer, err = core.timer.new("error-log-logger", process)
    if not timer then
        core.log.error("failed to create timer error-log-logger: ", err)
    else
        core.log.notice("succeed to create timer: error-log-logger")
    end
end

return _M
