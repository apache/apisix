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

local base = require("apisix.plugins.ai-drivers.ai-driver-base")
local core = require("apisix.core")
local setmetatable = setmetatable

local _M = { 
    name = "anthropic",
    host = "api.anthropic.com",
    path = "/v1/messages",
    port = 443,
}

local mt = { __index = setmetatable(_M, { __index = base }) }

local ANTHROPIC_VERSION = "2023-06-01"
local FINISH_REASON_MAP = {
    ["end_turn"] = "stop",
    ["max_tokens"] = "length",
    ["stop_sequence"] = "stop",
    ["tool_use"] = "tool_calls",
}

function _M.new(opts)
    return setmetatable(opts or {}, mt)
end

function _M:transform_request(conf, request_table)
    local anthropic_body = {
        model = conf.model,
        messages = {},
        max_tokens = request_table.max_tokens or 1024,
        stream = request_table.stream,
    }

    -- Protocol Translation: Extract system prompt
    for _, msg in ipairs(request_table.messages) do
        if msg.role == "system" then
            anthropic_body.system = msg.content
        else
            core.table.insert(anthropic_body.messages, {
                role = msg.role,
                content = msg.content
            })
        end
    end

    local headers = {
        ["Content-Type"] = "application/json",
        ["x-api-key"] = conf.api_key,
        ["anthropic-version"] = ANTHROPIC_VERSION,
    }

    return anthropic_body, headers
end

function _M:transform_response(response_body)
    local body = core.json.decode(response_body)
    if not body or not body.content then
        return nil, "invalid response from anthropic"
    end

    return {
        id = body.id,
        object = "chat.completion",
        created = os.time(),
        model = body.model,
        choices = {
            {
                index = 0,
                message = {
                    role = "assistant",
                    content = body.content[1].text,
                },
                finish_reason = FINISH_REASON_MAP[body.stop_reason] or "stop"
            }
        },
        usage = {
            prompt_tokens = body.usage.input_tokens,
            completion_tokens = body.usage.output_tokens,
            total_tokens = body.usage.input_tokens + body.usage.output_tokens
        }
    }
end

return _M
