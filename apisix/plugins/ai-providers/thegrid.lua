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

-- The Grid accepts `max_completion_tokens` like OpenAI, so the override is
-- mapped to that field rather than the legacy `max_tokens`.
local function rewrite_chat_request_body(body, override, force)
    if override.max_tokens then
        if force or (body.max_completion_tokens == nil and body.max_tokens == nil) then
            body.max_completion_tokens = override.max_tokens
            body.max_tokens = nil
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

return require("apisix.plugins.ai-providers.base").new(
    {
        host = "api.thegrid.ai",
        port = 443,
        -- The Consumption API validates the request and then answers with a
        -- documented 307 to its routing layer on the same host, which is where
        -- inference is actually fulfilled. The transport follows that hop so
        -- the Plugin observes the real response, and token usage stays visible
        -- to ai-rate-limiting and to ai-proxy-multi's fallback.
        follow_redirects = true,
        capabilities = {
            ["openai-chat"]      = {
                path = "/v1/chat/completions",
                rewrite_request_body = rewrite_chat_request_body,
            },
            ["openai-responses"] = {
                path = "/v1/responses",
                rewrite_request_body = rewrite_responses_request_body,
            },
        },
    }
)
