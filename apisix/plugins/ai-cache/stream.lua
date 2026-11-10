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

local pcall   = pcall
local require = require
local type    = type

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


-- Access-time analog of capturable(): predicts from the picked provider
-- whether a stream's framing is replayable, so access can skip the lookup.
function _M.provider_capturable(instance)
    local ok, provider = pcall(require,
                               "apisix.plugins.ai-providers." .. instance.provider)
    if not ok or type(provider) ~= "table" then
        return true
    end
    local framing = provider.streaming_framing
    return not framing or framing == "sse"
end


-- True when the buffer ends, at a frame boundary, with the client protocol's
-- terminal event. Deliberately NOT ctx.var.llm_request_done, which is also set
-- on aborts. The boundary check guards truncation: sse.decode treats a trailing
-- partial frame as a complete event, so a cut-off buffer could otherwise pass.
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
    local events = sse.decode(body)
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
