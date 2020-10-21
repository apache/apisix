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
local sleep = ngx.sleep
local exiting = ngx.worker.exiting
local plugin_name = "error-log-logger"
local ngx = ngx
local tcp = ngx.socket.tcp
local timer_at = ngx.timer.at


local schema = {
    type = "object",
    properties = {
        host = {type = "string"},
        port = {type = "integer"},
        loglevel = {type = "string", default = "WARN"},
        uri_path = {type = "string"},
        name = {type = "string", default = "error logger"},
        timeout = {type = "integer", minimum = 1, default = 3},
        protocol_type = {type = "string", default = "tcp", enum = {"tcp", "http"}},
        max_retry_times = {type = "integer", minimum = 1, default = 1},
        retry_interval = {type = "integer", minimum = 0, default = 1},
        tls = {type = "boolean", default = false}
    },
    required = {"host", "port"}
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

local _M = {
    version = 0.1,
    priority = 1091,
    name = plugin_name,
    schema = schema,
}


function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end

local report = function(premature, errlog, level)
    if premature then
        return
    end

    local sock, soc_err = tcp()

    if not sock then
        core.log.error("failed to init the socket " .. soc_err)
        return
    end
    local conf ={
            host = "127.0.0.1",
            port = 33333,
            timeout = 3,
    } -- will be reload from plugin's config

    sock:settimeout(conf.timeout)

    local ok, err = sock:connect(conf.host, conf.port)

    if not ok then
        core.log.warn("connect to the server failed for " .. err)
    end

    while ( not exiting()) do
        local logs, err = errlog.get_logs(10)
        if #logs == 0 then
            sleep(0.2)
        elseif #logs < 0 then
            core.log.error("errlog.get_logs failed for " .. err)
        else
            -- send to the server
            for i = 1, #logs, 3 do
                if logs[i] <= level then --ommit the lower log producted at the initial
                    local bytes, err = sock:send(logs[i + 2])
                    if not bytes then
                        core.log.warn("send data  failed for " , err, ", the data:", logs[i + 2] )
                    end
                end
            end
        end
	end

end

function _M.init()
    if ngx.get_phase() ~= "init" and ngx.get_phase() ~= "init_worker"  then
        return
    end
    local default_level_str = "warn"
    local level = log_level[string.upper(default_level_str)]
    if not level then
        core.log.error("input a wrong loglevel.")
        return
    end
    core.log.error("set   loglevel WARN.")
    local errlog = require "ngx.errlog"
    local status, err = errlog.set_filter_level(level)
    if not status then
        core.log.error("failed to set filter level by ngx.errlog, the error is :", err)
        return
    end
    timer_at(0, report, errlog, level)
end

return _M