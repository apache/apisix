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

--- Passthrough protocol adapter.
-- Catch-all protocol that matches any non-empty request body when no other
-- protocol matches. Proxies request/response without any transformation.
-- Only model rewrite, auth header injection, and override.endpoint work.

local type = type
local next = next

local _M = {}


function _M.matches(body, ctx)
    return type(body) == "table" and next(body) ~= nil
end


function _M.is_streaming(body)
    return type(body) == "table" and body.stream == true
end


function _M.prepare_outgoing_request(_)
end


function _M.parse_sse_event(_, _, _)
    return { type = "skip" }
end


function _M.extract_response_text(_)
    return nil
end


function _M.extract_usage(_)
    return nil, nil
end


function _M.extract_request_content(_)
    return {}
end


function _M.get_messages(_)
    return {}
end


function _M.prepend_messages(_, _)
end


function _M.append_messages(_, _)
end


function _M.get_request_content(_)
    return nil
end


function _M.build_simple_request(_, _, _)
    return {}
end


function _M.build_deny_response(_)
    return ""
end


function _M.empty_usage()
    return { prompt_tokens = 0, completion_tokens = 0, total_tokens = 0 }
end


function _M.is_data_event(_)
    return false
end


function _M.is_done_event(_)
    return false
end


function _M.build_done_event()
    return "data: [DONE]"
end


return _M
