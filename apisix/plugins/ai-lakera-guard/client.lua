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

local type = type

local _M = {}


-- Call Lakera Guard /v2/guard with the given content.
--
-- The whole extracted request content is sent as a single message, with no role
-- distinction, consistent with ai-aliyun-content-moderation.
--
-- On success returns a result table; on the Lakera-unreachable path (timeout,
-- connection error, non-2xx, decode failure) returns nil + an error string.
--
-- result fields:
--   flagged      (boolean)     — Lakera's primary enforcement signal
--   breakdown    (array|nil)   — Lakera's per-detector results, passed through
--                                verbatim and unfiltered (both detected and
--                                non-detected entries) so the full verdict can be
--                                logged exactly as Lakera returned it; selecting
--                                which detectors to surface is left to the caller
--   request_uuid (string|nil)  — Lakera trace id, when present
function _M.scan(conf, content)
    local body = {
        messages = { { role = "user", content = content } },
        -- Always request the per-detector breakdown so flagged verdicts can be
        -- logged in full (with confidence results); the client-facing reveal is
        -- gated separately by reveal_failure_categories.
        breakdown = true,
    }
    if conf.project_id then
        body.project_id = conf.project_id
    end
    -- A future PII-redaction phase should set `body.payload = true` to have Lakera
    -- return the matched PII / profanity / regex spans. We don't request it here:
    -- this phase doesn't consume those spans, and they can contain sensitive text
    -- we shouldn't pull into the gateway unnecessarily.

    local headers = {
        ["Content-Type"] = "application/json",
    }
    if conf.api_key and conf.api_key ~= "" then
        headers["Authorization"] = "Bearer " .. conf.api_key
    end

    local httpc = http.new()
    httpc:set_timeout(conf.timeout)

    local res, err = httpc:request_uri(conf.lakera_endpoint, {
        method = "POST",
        body = core.json.encode(body),
        headers = headers,
        ssl_verify = conf.ssl_verify,
    })
    if not res then
        return nil, "failed to request Lakera Guard: " .. (err or "unknown error")
    end
    if res.status ~= 200 then
        return nil, "Lakera Guard returned status " .. res.status
    end

    local data, decode_err = core.json.decode(res.body)
    if not data then
        return nil, "failed to decode Lakera Guard response: "
                        .. (decode_err or "unknown error")
    end

    return {
        flagged = data.flagged == true,
        breakdown = type(data.breakdown) == "table" and data.breakdown or nil,
        request_uuid = data.metadata and data.metadata.request_uuid,
    }
end


return _M
