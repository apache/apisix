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
-- Eden AI exposes an OpenAI-compatible Chat Completions endpoint under
-- https://api.edenai.run/v3. Models are addressed as "provider/model"
-- strings (e.g. "openai/gpt-4o") and authenticated with
-- "Authorization: Bearer <key>", which the generic auth.header option covers.
-- The endpoint is served natively, so no request conversion is needed; only
-- the output token field is mapped here. Eden AI accepts both max_tokens and
-- max_completion_tokens; max_tokens is the field its own documentation uses.

local function rewrite_chat_request_body(body, override, force)
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
            ["openai-chat"] = {
                path = "/v3/chat/completions",
                rewrite_request_body = rewrite_chat_request_body,
            },
        },
    }
)
