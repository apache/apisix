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
local ngx = ngx
local tcp = ngx.socket.tcp
--local exiting = ngx.worker.exiting
local errlog = require "ngx.errlog"

local timer
local schema = {
    type = "object",
    properties = {},
    additionalProperties = false,
}
-- local schema = {
--     type = "object",
--     properties = {
--         host = {type = "string"},
--         port = {type = "integer"},
--         loglevel = {type = "string", default = "WARN"},
--         uri_path = {type = "string"},
--         name = {type = "string", default = "error logger"},
--         timeout = {type = "integer", minimum = 1, default = 3},
--         protocol_type = {type = "string", default = "tcp", enum = {"tcp", "http"}},
--         max_retry_times = {type = "integer", minimum = 1, default = 1},
--         retry_interval = {type = "integer", minimum = 0, default = 1},
--         tls = {type = "boolean", default = false}
--     },
--     required = {"host", "port"}
-- }

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


local function report()
    local local_conf = core.config.local_conf()
    local host, port
    local timeout = 3
    local keepalive = 3
    local level = "warn"
    if try_attr(local_conf, "plugin_attr", plugin_name) then
        local attr = local_conf.plugin_attr[plugin_name]
        host = attr.host
        port = attr.port
        level = attr.loglevel or level
        timeout = attr.timeout or timeout
        keepalive = attr.keepalive or keepalive
    end
    level = log_level[string.upper(level)]

    local status, err = errlog.set_filter_level(level)
    if not status then
        core.log.error("failed to set filter level by ngx.errlog, the error is :", err)
        return
    end

    local sock, soc_err = tcp()
    if not sock then
        core.log.error("failed to init the socket " .. soc_err)
        return
    end
    sock:settimeout(timeout*1000)
    local ok, err = sock:connect(host, port)
    if not ok then
        core.log.info("connect to the server failed for " .. err)
        return
    end
    local logs = errlog.get_logs(10)
    while ( logs and #logs>0 ) do
        for i = 1, #logs, 3 do
            if logs[i] <= level then --ommit the lower log producted at the initial
                local bytes, err = sock:send(logs[i + 2])
                if not bytes then
                    core.log.info("send data  failed for " , err, ", the data:", logs[i + 2] )
                    return
                end
            end
        end
        logs = errlog.get_logs(10)
	end
    sock:setkeepalive(keepalive*1000)
end

function _M.init()
    if ngx.get_phase() ~= "init" and ngx.get_phase() ~= "init_worker"  then
        return
    end

    if timer then
        return
    end
    local err
    timer, err = core.timer.new("error-log-logger", report)
    if not timer then
        core.log.error("failed to create timer error-log-logger: ", err)
    else
        core.log.notice("succeed to create timer: error-log-logger")
    end
end

return _M