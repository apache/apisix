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

-- Mock LLM upstream that commits a 200 SSE response and then drops the
-- connection mid-body. Writing the response on the raw downstream socket is
-- what makes the truncation possible: through the normal nginx output chain the
-- terminating chunk is always appended, which is a clean EOF rather than the
-- transport error this mock has to produce.
local ngx = ngx

local _M = {}

local CRLF = string.char(13, 10)

local DONE_STREAM = table.concat({
    'data: {"id":"chatcmpl-1","object":"chat.completion.chunk",'
    .. '"choices":[{"index":0,"delta":{"content":"hello"},"finish_reason":null}]}',
    "",
    "data: [DONE]",
    "",
    "",
}, "\n")


local function take_over()
    ngx.req.read_body()
    local sock, err = ngx.req.socket(true)
    if not sock then
        ngx.log(ngx.ERR, "failed to take over the downstream socket: ", err)
        return nil
    end
    sock:send("HTTP/1.1 200 OK" .. CRLF
              .. "Content-Type: text/event-stream" .. CRLF
              .. "Transfer-Encoding: chunked" .. CRLF
              .. "Connection: keep-alive" .. CRLF .. CRLF)
    return sock
end


-- Sends every event in `events` as its own chunk, then closes without the
-- terminating zero-length chunk, so the client's body reader fails with
-- "closed" after the events have already been delivered.
function _M.serve(events)
    local sock = take_over()
    if not sock then
        return
    end
    for _, event in ipairs(events) do
        sock:send(string.format("%x", #event) .. CRLF .. event .. CRLF)
    end
    return ngx.exit(444)
end


local done_then_truncate_hits = 0

-- First call answers with a [DONE]-only stream. Behind a protocol converter
-- that yields no downstream event for it, the attempt sets llm_request_done
-- while output_sent stays false, so EOF becomes the 502 that ai-proxy-multi
-- falls back on. Every later call emits one real event and then truncates,
-- which is the attempt that must not inherit the first one's completion state.
function _M.serve_done_then_truncate()
    done_then_truncate_hits = done_then_truncate_hits + 1
    if done_then_truncate_hits == 1 then
        ngx.header["Content-Type"] = "text/event-stream"
        ngx.print("data: [DONE]\n\n")
        return ngx.flush(true)
    end
    return _M.serve({
        'data: {"id":"chatcmpl-1","object":"chat.completion.chunk",'
        .. '"choices":[{"index":0,"delta":{"content":"hello"},'
        .. '"finish_reason":null}]}\n\n',
        -- a usage event, so the content-moderation final_packet path has an
        -- assembled completion to work with before the transport dies
        'data: {"id":"chatcmpl-1","object":"chat.completion.chunk",'
        .. '"choices":[],"usage":{"prompt_tokens":1,'
        .. '"completion_tokens":1,"total_tokens":2}}\n\n',
    })
end


local aborts = 0

-- First call closes right after the headers, before any body byte; every later
-- call streams a complete response.
function _M.serve_abort_once()
    aborts = aborts + 1
    if aborts > 1 then
        ngx.header["Content-Type"] = "text/event-stream"
        ngx.print(DONE_STREAM)
        return ngx.flush(true)
    end
    if not take_over() then
        return
    end
    return ngx.exit(444)
end


-- Minimal AWS Comprehend detectToxicContent stand-in: answers one clean result
-- per submitted segment. The truncation tests only need the moderation plugin to
-- reach its terminator-synthesis branch, not a particular verdict.
function _M.serve_clean_comprehend()
    local json = require("cjson.safe")
    ngx.req.read_body()
    local body = json.decode(ngx.req.get_body_data() or "{}") or {}
    local results = {}
    for i in ipairs(body.TextSegments or {}) do
        results[i] = {
            Toxicity = 0.01,
            Labels = {
                { Name = "PROFANITY", Score = 0.01 },
                { Name = "HATE_SPEECH", Score = 0.01 },
                { Name = "INSULT", Score = 0.01 },
                { Name = "GRAPHIC", Score = 0.01 },
                { Name = "HARASSMENT_OR_ABUSE", Score = 0.01 },
                { Name = "SEXUAL", Score = 0.01 },
                { Name = "VIOLENCE_OR_THREAT", Score = 0.01 },
            },
        }
    end
    ngx.status = 200
    ngx.header["Content-Type"] = "application/json"
    ngx.say(json.encode({ ResultList = results }))
end


return _M
