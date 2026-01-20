--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License,  Version 2.0
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
local core = require("apisix.core" )
local json = require("apisix.core.json")
local ai_driver_base = require("apisix.plugins.ai-drivers.ai-driver-base")

local _M = {}
local mt = { __index = setmetatable(_M, { __index = ai_driver_base }) }

function _M.new(opts)
    local self = ai_driver_base.new(opts)
    return setmetatable(self, mt)
end

function _M.transform_request(self, openai_body)
    local anthropic_body = {
        model = openai_body.model,
        max_tokens = openai_body.max_tokens or 4096,
        stream = openai_body.stream,
        messages = {}
    }

    local system_prompt = ""
    for _, msg in ipairs(openai_body.messages) do
        if msg.role == "system" then
            system_prompt = system_prompt .. msg.content
        else
            table.insert(anthropic_body.messages, {
                role = msg.role,
                content = msg.content
            })
        end
    end

    if system_prompt ~= "" then
        anthropic_body.system = system_prompt
    end

    return anthropic_body
end

function _M.transform_response(self, anthropic_res)
    local body = json.decode(anthropic_res.body)
    if not body then
        return nil, "failed to decode response"
    end

    return {
        id = body.id,
        object = "chat.completion",
        created = ngx.time(),
        model = body.model,
        choices = {
            {
                index = 0,
                message = {
                    role = "assistant",
                    content = body.content[1].text
                },
                finish_reason = body.stop_reason
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
