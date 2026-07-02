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
--
-- Streaming (SSE) capture + replay policy for ai-cache: body_filter buffers
-- the raw client-wire frames, log() stores them once complete, serve_hit
-- replays them as one text/event-stream body.
--
local sse       = require("apisix.plugins.ai-transport.sse")
local protocols = require("apisix.plugins.ai-protocols")

local _M = {}

-- Replay format tag stored on every cache entry (L1 envelope and L2 doc).
_M.FORMAT_JSON = "json"   -- single-shot application/json body
_M.FORMAT_SSE  = "sse"    -- raw text/event-stream frames incl. terminal event


-- Replayable: single-shot (no framing) or SSE. Binary framings
-- (aws-eventstream) are not.
function _M.capturable(ctx)
    local framing = ctx.ai_stream_framing
    return not framing or framing == "sse"
end


-- End offset of the last plain-text `needle` ending at or before `limit`, or nil.
local function find_last(s, needle, limit)
    local last, init = nil, 1
    while true do
        local i, j = s:find(needle, init, true)
        if not i or j > limit then
            return last
        end
        last = j
        init = i + 1
    end
end


-- True when the buffer ends, at a frame boundary, with the client protocol's
-- terminal event ([DONE], message_stop, response.completed). Deliberately NOT
-- ctx.var.llm_request_done, which is also set on aborts; log() separately
-- refuses aborted captures. Only the terminal frame is decoded: full-buffer
-- sse.decode is quadratic, and without the boundary check a frame truncated
-- mid-write could parse into an event that is_done_event accepts.
function _M.stream_completed(ctx, body)
    if not body or body == "" then
        return false
    end
    local proto = ctx.ai_client_protocol and protocols.get(ctx.ai_client_protocol)
    if not (proto and proto.is_done_event) then
        return false
    end
    local tail = body:sub(-256)
    if not (tail:find("\n\n%s*$") or tail:find("\r\n\r\n%s*$")) then
        return false
    end
    -- last non-whitespace byte = end of the terminal frame's content
    local content_end = #body
    while content_end > 0 do
        local b = body:byte(content_end)
        if b ~= 10 and b ~= 13 and b ~= 32 and b ~= 9 then
            break
        end
        content_end = content_end - 1
    end
    local lf   = find_last(body, "\n\n", content_end) or 0
    local crlf = find_last(body, "\r\n\r\n", content_end) or 0
    local frame_start = (lf > crlf and lf or crlf) + 1
    local events = sse.decode(body:sub(frame_start))
    local last = events[#events]
    return last ~= nil and proto.is_done_event(last) == true
end


local function looks_like_sse(body)
    return body:find("^%s*data:") or body:find("^%s*event:")
        or body:find("^%s*:") or body:find("^%s*id:") or body:find("^%s*retry:")
end


-- Format tag to store for a MISS capture, or nil when it must not be cached
-- (incomplete stream, SSE bytes without framing, non-SSE framing).
function _M.capture_format(ctx, body)
    local framing = ctx.ai_stream_framing
    if not framing then
        if looks_like_sse(body) then
            return nil
        end
        return _M.FORMAT_JSON
    end
    if framing ~= "sse" or not _M.stream_completed(ctx, body) then
        return nil
    end
    return _M.FORMAT_SSE
end


return _M
