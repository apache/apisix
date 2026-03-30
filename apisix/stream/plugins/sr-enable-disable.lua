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

-- Stream route gating plugin for APISIX.
--
-- Attach to any stream route to control whether it accepts connections.
-- When the "enabled" flag is truthy, traffic flows normally; otherwise
-- connections are refused with an optional rejection message.
--
-- Note: This plugin operates at the stream level, so it does not have
-- access to HTTP-specific features like status codes or headers. Instead,
-- it simply accepts or rejects TCP/TLS connections based on the "enabled" flag.
--
-- For configuration and usage details, see:
-- docs/en/latest/plugins/sr-enable-disable.md

local log        = require("apisix.core").log
local checker    = require("apisix.core").schema

local NAME = "sr-enable-disable"
local DEFAULT_REJECTION = "Stream route in disabled state."

local conf_schema = {
    type = "object",
    properties = {
        enabled = {
            type = "boolean",
        },
        decline_msg = {
            type = "string",
            default = DEFAULT_REJECTION,
        },
    },
    required = {"enabled"},
    additionalProperties = false,
}

local _M = {
    version  = 1.0,
    priority = 10000,
    name     = NAME,
    schema   = conf_schema,
}


function _M.check_schema(conf)
    return checker.check(conf_schema, conf)
end


local function reject_connection(reason)
    local sock, err = ngx.req.socket()
    if not sock then
        log.error(NAME, ": failed to get downstream socket: ", err)
        return
    end

    sock:send(reason)
    sock:close()
end


function _M.preread(conf, ctx)
    if conf.enabled then
        return            -- route is active, let it through
    end

    local reason = conf.decline_msg or DEFAULT_REJECTION
    log.warn(NAME, ": refusing stream connection - ", reason)

    reject_connection(reason)

    return 503
end


return _M
