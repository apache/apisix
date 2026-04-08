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

--- OpenAI Embeddings protocol adapter.
-- Detected by body: any request with body.input (catch-all after responses).
-- Non-streaming only — embeddings do not support SSE.

local core = require("apisix.core")
local type = type
local ipairs = ipairs

local _M = {}


function _M.matches(body, ctx)
    return type(body) == "table" and body.input ~= nil
end


function _M.is_streaming(_)
    return false
end


function _M.prepare_request(body, _, _)
    return body, body and body.model
end


function _M.extract_usage(res_body)
    if not res_body or not res_body.usage then
        return nil
    end
    return {
        prompt_tokens = res_body.usage.prompt_tokens or 0,
        completion_tokens = 0,
        total_tokens = res_body.usage.total_tokens or 0,
    }, res_body.usage
end


function _M.extract_response_text(_)
    return nil
end


function _M.parse_sse_event(_, _, _)
    return { type = "skip" }
end


function _M.build_simple_request(_, user_content, opts)
    local body = {
        input = user_content,
    }
    if opts and opts.model then
        body.model = opts.model
    end
    return body
end


--- Extract all text content from a request body for moderation.
function _M.extract_request_content(body)
    local contents = {}
    if not body then
        return contents
    end
    local input = body.input
    if type(input) == "string" then
        contents[1] = input
    elseif type(input) == "table" then
        for _, item in ipairs(input) do
            if type(item) == "string" then
                core.table.insert(contents, item)
            end
        end
    end
    return contents
end


function _M.get_messages(body)
    local messages = {}
    if body and body.input then
        if type(body.input) == "string" then
            core.table.insert(messages, {role = "user", content = body.input})
        end
    end
    return messages
end


function _M.prepend_messages(_, _)
end


function _M.append_messages(_, _)
end


function _M.get_request_content(body)
    return body and body.input
end
-- opts: {text, model, usage, stream}
function _M.build_deny_response(opts)
    return core.json.encode({
        error = {
            message = opts.text,
            type = "content_policy_violation",
        },
    })
end


--- Build an empty usage object with zero values.
function _M.empty_usage()
    return { prompt_tokens = 0, completion_tokens = 0, total_tokens = 0 }
end


--- Check if an SSE event is a data event (no-op for embeddings).
function _M.is_data_event(_)
    return false
end


--- Check if an SSE event is the terminal/done event (no-op for embeddings).
function _M.is_done_event(_)
    return false
end


--- Build a terminal SSE event string (no-op for embeddings).
function _M.build_done_event()
    return ""
end


return _M
