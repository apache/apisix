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
local http = require("resty.http")
local url  = require("socket.url")


local _M = {}


function _M.scan(conf, messages, project_id)
    local body = {
        messages = messages,
        breakdown = true,
    }
    if project_id then
        body.project_id = project_id
    end

    local body_str, err = core.json.encode(body)
    if not body_str then
        return nil, nil, "failed to encode request body: " .. (err or "unknown")
    end

    local parsed = url.parse(conf.endpoint.url)
    if not parsed or not parsed.host then
        return nil, nil, "invalid endpoint.url: " .. (conf.endpoint.url or "")
    end

    local httpc = http.new()
    httpc:set_timeout(conf.endpoint.timeout_ms)

    local ok, connect_err = httpc:connect({
        scheme = parsed.scheme or "https",
        host = parsed.host,
        port = parsed.port,
        ssl_verify = conf.endpoint.ssl_verify,
        ssl_server_name = parsed.host,
        pool_size = conf.endpoint.keepalive and conf.endpoint.keepalive_pool,
    })
    if not ok then
        return nil, nil, "failed to connect to lakera: " .. (connect_err or "unknown")
    end

    local res, req_err = httpc:request({
        method = "POST",
        path = parsed.path or "/v2/guard",
        body = body_str,
        headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Bearer " .. conf.endpoint.api_key,
        },
    })
    if not res then
        return nil, nil, "failed to call lakera: " .. (req_err or "unknown")
    end

    local raw_body, read_err = res:read_body()
    if not raw_body then
        return nil, nil, "failed to read lakera response: " .. (read_err or "unknown")
    end

    if conf.endpoint.keepalive then
        local keep_ok, keep_err = httpc:set_keepalive(
            conf.endpoint.keepalive_timeout_ms,
            conf.endpoint.keepalive_pool
        )
        if not keep_ok then
            core.log.warn("ai-lakera-guard: failed to set keepalive: ", keep_err)
        end
    end

    if res.status ~= 200 then
        return nil, nil, "lakera returned non-200 status: " .. res.status
                            .. ", body: " .. raw_body
    end

    local decoded, decode_err = core.json.decode(raw_body)
    if not decoded then
        return nil, nil, "failed to decode lakera response: " .. (decode_err or "unknown")
                            .. ", body: " .. raw_body
    end

    local detector_types = {}
    if type(decoded.breakdown) == "table" then
        for _, entry in ipairs(decoded.breakdown) do
            if entry.detected and type(entry.detector_type) == "string" then
                core.table.insert(detector_types, entry.detector_type)
            end
        end
    end

    return decoded.flagged == true, detector_types, nil
end


return _M
