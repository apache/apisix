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
local _M = {}

local openai_compatible_chat_schema = {
        type = "object",
        properties = {
            messages = {
                type = "array",
                minItems = 1,
                items = {
                    properties = {
                        role = {
                            type = "string",
                            enum = {"system", "user", "assistant"}
                        },
                        content = {
                            type = "string",
                            minLength = "1",
                        },
                    },
                    additionalProperties = false,
                    required = {"role", "content"},
                },
            }
        },
        required = {"messages"}
    }

local openai_compatible_list = {
    "openai",
    "deepseek",
    "aimlapi",
    "anthropic",
    "openai-compatible",
    "azure-openai",
    "openrouter",
    "vertex-ai",
    "gemini",
}

-- Anthropic native protocol allows a top-level "system" field
-- and content can be a string or array; we keep validation minimal here.
local anthropic_native_chat_schema = {
    type = "object",
    properties = {
        messages = {
            type = "array",
            minItems = 1,
            items = {
                properties = {
                    role    = { type = "string", enum = {"user", "assistant"} },
                    content = {},  -- string or array of content blocks
                },
                required = {"role", "content"},
            },
        }
    },
    required = {"messages"}
}

-- Native Anthropic protocol providers (not OpenAI-compatible)
local anthropic_native_list = {
    "anthropic-native",
}

-- Export list of all providers (OpenAI-compatible + native Anthropic)
_M.providers = {}
for _, p in ipairs(openai_compatible_list) do
    _M.providers[#_M.providers + 1] = p
end
for _, p in ipairs(anthropic_native_list) do
    _M.providers[#_M.providers + 1] = p
end

_M.chat_request_schema = {}

do
    local openai_compatible_kv = {}
    for _, provider in ipairs(openai_compatible_list) do
        _M.chat_request_schema[provider] = openai_compatible_chat_schema
        openai_compatible_kv[provider] = true
    end

    for _, provider in ipairs(anthropic_native_list) do
        _M.chat_request_schema[provider] = anthropic_native_chat_schema
    end

    function _M.is_openai_compatible_provider(provider)
        return openai_compatible_kv[provider] == true
    end
end

return _M
