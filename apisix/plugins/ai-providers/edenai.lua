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

--- Eden AI provider.
-- Eden AI exposes its LLM gateway under https://api.edenai.run/v3 with
-- OpenAI-compatible Chat Completions, Responses and Embeddings endpoints and
-- an Anthropic Messages pass-through endpoint. Models are addressed as
-- "provider/model" strings (e.g. "openai/gpt-latest") and authenticated with
-- "Authorization: Bearer <key>", which the generic auth.header option covers.
-- Every protocol below is served natively, so no request conversion is
-- needed; only the per-protocol output token field is mapped here.

local function rewrite_chat_request_body(body, override, force)
    -- Eden AI accepts both max_tokens and max_completion_tokens on the chat
    -- endpoint; max_tokens is the field its own documentation uses.
    if override.max_tokens then
        if force or body.max_tokens == nil then
            body.max_tokens = override.max_tokens
        end
    end
end


local function rewrite_responses_request_body(body, override, force)
    if override.max_tokens then
        if force or body.max_output_tokens == nil then
            body.max_output_tokens = override.max_tokens
        end
    end
end


local function rewrite_messages_request_body(body, override, force)
    if override.max_tokens then
        if force or body.max_tokens == nil then
            body.max_tokens = override.max_tokens
        end
    end
end

return require("apisix.plugins.ai-providers.base").new(
    {
        host = "api.edenai.run",
        port = 443,
        capabilities = {
            ["openai-chat"]        = {
                path = "/v3/chat/completions",
                rewrite_request_body = rewrite_chat_request_body,
            },
            ["openai-responses"]   = {
                path = "/v3/responses",
                rewrite_request_body = rewrite_responses_request_body,
            },
            ["openai-embeddings"]  = { path = "/v3/embeddings" },
            ["anthropic-messages"] = {
                path = "/v3/v1/messages",
                rewrite_request_body = rewrite_messages_request_body,
            },
        },
    }
)
