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
local core     = require("apisix.core")
local log_util = require("apisix.plugins.log-util")
local plugin_name = "udp-logger"
local ngx = ngx

local timer_at = ngx.timer.at
local udp = ngx.socket.udp

local schema = {
    type = "object",
    properties = {
        host = {type = "string"},
        port = {type = "integer", minimum = 0},
        timeout = {type = "integer", minimum = 1, default= 1000} -- timeout in milliseconds
    },
    required = {"host", "port"}
}


local _M = {
    version = 0.1,
    priority = 400,
    name = plugin_name,
    schema = schema,
}

function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end

local function log(premature, conf, log_message)
    if premature then
        return
    end

    local sock = udp()
    sock:settimeout(conf.timeout)

    local ok, err = sock:setpeername(conf.host, conf.port)
    if not ok then
        core.log.error("failed to connect to UDP server: host[", conf.host, "] port[", conf.port, "] ", err)
        return
    end

    ok, err = sock:send(log_message)
    if not ok then
        core.log.error("failed to send data to UDP server: host[", conf.host, "] port[", conf.port, "] ", err)
    end

    ok, err = sock:close()
    if not ok then
        core.log.error("failed to close the UDP connection, host[", conf.host, "] port[", conf.port, "] ", err)
    end
end


function _M.log(conf)
    return timer_at(0, log, conf, core.json.encode(log_util.get_full_log(ngx)))
end

return _M

