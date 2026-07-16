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

--- Shared helpers for AI plugins bound at Consumer/Service level.
-- A Consumer-bound AI plugin may receive requests it cannot handle: plain HTTP
-- traffic, requests that never passed through ai-proxy/ai-proxy-multi, or an
-- unsupported content-type/protocol. This module standardizes that handling via
-- a configurable `fail_mode`.

local core = require("apisix.core")
local re_gsub = ngx.re.gsub
local sub = string.sub

local _M = {}

local MAX_REASON_LEN = 256


-- `reason` may embed request-controlled values (e.g. the Content-Type header),
-- so strip control characters and cap the length before logging to avoid
-- log forging / injection.
local function sanitize_reason(reason)
    local safe = reason or "unsupported request protocol"
    safe = re_gsub(safe, "[[:cntrl:]]", " ", "jo")
    if #safe > MAX_REASON_LEN then
        safe = sub(safe, 1, MAX_REASON_LEN)
    end
    return safe
end


--- Build the `fail_mode` schema fragment for a plugin.
-- Plugins default to "skip" so that Consumer-bound AI plugins let non-AI traffic
-- pass through unchecked; operators can opt into "warn" or "error" (fail-closed)
-- when every request from the binding must be an AI request.
-- @param default string One of "skip" | "warn" | "error"
-- @return table schema fragment
function _M.schema_property(default)
    return {
        type = "string",
        enum = {"skip", "warn", "error"},
        default = default,
        description = "Behavior when the request protocol/format is not supported "
            .. "by this AI plugin (e.g. non-AI HTTP traffic on a Consumer-bound "
            .. "plugin, or a request that did not pass through ai-proxy). "
            .. "skip: pass the request through unchecked; "
            .. "warn: pass through and log a warning; "
            .. "error: reject the request.",
    }
end


--- Decide what to do for a request this plugin cannot handle.
-- For "error" mode it returns the caller-supplied code/body so the request is
-- rejected. For "skip"/"warn" it logs (at info/warn level), then returns
-- handled=false so the caller can `return` to let the request pass through
-- unchecked.
-- @param mode string conf.fail_mode
-- @param plugin_name string the plugin name, used in the logs
-- @param ctx table request context
-- @param reason string human-readable reason, for logs
-- @param err_code number return code used when mode == "error"
-- @param err_body any return body used when mode == "error"
-- @return boolean handled, number|nil code, any|nil body
function _M.on_unsupported(mode, plugin_name, ctx, reason, err_code, err_body)
    if mode == "error" then
        return true, err_code, err_body
    end

    local msg = plugin_name .. " skipped: " .. sanitize_reason(reason)
    if mode == "warn" then
        core.log.warn(msg)
    else
        core.log.info(msg)
    end
    return false
end


return _M
