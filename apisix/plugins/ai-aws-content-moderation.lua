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
require("resty.aws.config") -- to read env vars before initing aws module

local core      = require("apisix.core")
local protocols = require("apisix.plugins.ai-protocols")
local binding   = require("apisix.plugins.ai-protocols.binding")
local sse       = require("apisix.plugins.ai-transport.sse")
local aws       = require("resty.aws")
local aws_instance

local http = require("resty.http")

local ngx      = ngx
local ngx_ok   = ngx.OK
local pairs    = pairs
local unpack   = unpack
local type     = type
local ipairs   = ipairs
local table    = table
local str_byte = string.byte
local str_sub  = string.sub
local HTTP_INTERNAL_SERVER_ERROR = ngx.HTTP_INTERNAL_SERVER_ERROR
local HTTP_BAD_REQUEST = ngx.HTTP_BAD_REQUEST

-- DetectToxicContent takes at most 10 text segments per call, each at most
-- 1 KB, with the whole list capped at 10 KB. Anything over that is rejected
-- with TextSizeLimitExceededException, so content is split and batched to fit.
-- https://docs.aws.amazon.com/comprehend/latest/APIReference/API_DetectToxicContent.html
local MAX_SEGMENT_BYTES = 1024
local MAX_SEGMENTS_PER_CALL = 10
local MAX_CALL_BYTES = 10000

local moderation_categories_pattern = "^(PROFANITY|HATE_SPEECH|INSULT|"..
                                      "HARASSMENT_OR_ABUSE|SEXUAL|VIOLENCE_OR_THREAT)$"
local schema = {
    type = "object",
    properties = {
        comprehend = {
            type = "object",
            properties = {
                access_key_id = { type = "string" },
                secret_access_key = { type = "string" },
                region = { type = "string" },
                endpoint = {
                    type = "string",
                    pattern = [[^https?://]]
                },
                ssl_verify = {
                    type = "boolean",
                    default = true
                }
            },
            required = { "access_key_id", "secret_access_key", "region", }
        },
        moderation_categories = {
            type = "object",
            patternProperties = {
                [moderation_categories_pattern] = {
                    type = "number",
                    minimum = 0,
                    maximum = 1
                }
            },
            additionalProperties = false
        },
        moderation_threshold = {
            type = "number",
            minimum = 0,
            maximum = 1,
            default = 0.5
        },
        check_request = { type = "boolean", default = true },
        check_response = { type = "boolean", default = false },
        request_check_length_limit = {
            type = "integer",
            minimum = 1,
            maximum = MAX_SEGMENT_BYTES,
            default = 1000,
            description = "max bytes of request content per Comprehend text segment; " ..
                          "longer content is split into several segments",
        },
        response_check_length_limit = {
            type = "integer",
            minimum = 1,
            maximum = MAX_SEGMENT_BYTES,
            default = 1000,
            description = "max bytes of response content per Comprehend text segment; " ..
                          "longer content is split into several segments",
        },
        stream_check_mode = {
            type = "string",
            enum = { "realtime", "final_packet" },
            default = "final_packet",
            description = "realtime: moderate batches while the response streams, replacing " ..
                          "the rest of the stream on a hit | final_packet: moderate the " ..
                          "assembled response and annotate the last chunk with risk_level.",
        },
        stream_check_cache_size = {
            type = "integer",
            minimum = 1,
            default = 128,
            description = "max characters per moderation batch in realtime mode",
        },
        stream_check_interval = {
            type = "number",
            minimum = 0.1,
            default = 3,
            description = "seconds between batch checks in realtime mode",
        },
        deny_code = {
            type = "integer",
            minimum = 200,
            maximum = 599,
            default = 200,
            description = "HTTP status returned on a deny. Defaults to 200 so the " ..
                          "provider-compatible refusal parses as a normal completion in " ..
                          "client SDKs; set a 4xx to surface denies as HTTP errors instead.",
        },
        deny_message = { type = "string" },
        timeout = {
            type = "integer",
            minimum = 1,
            default = 10000,
            description = "Comprehend request timeout in milliseconds",
        },
        keepalive = {
            type = "boolean",
            default = true,
            description = "if true, keep the Comprehend connection alive for reuse",
        },
        keepalive_timeout = {
            type = "integer",
            minimum = 1000,
            default = 60000,
            description = "idle time in milliseconds before a pooled Comprehend " ..
                          "connection is closed",
        },
        fail_mode = binding.schema_property("skip"),
    },
    encrypt_fields = { "comprehend.secret_access_key" },
    required = { "comprehend" },
}


local _M = {
    version  = 0.1,
    priority = 1031,
    name     = "ai-aws-content-moderation",
    schema   = schema,
}


function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end


-- Comprehend scores content, it doesn't grade it, so the verdict is binary
-- against the configured thresholds. Report it through the same ctx var the
-- aliyun plugin uses so logging and downstream consumers stay uniform.
local function set_risk_level(ctx, flagged)
    if flagged then
        ctx.var.llm_content_risk_level = "high"
    elseif ctx.var.llm_content_risk_level ~= "high" then
        ctx.var.llm_content_risk_level = "none"
    end
end


-- One Comprehend client per request: realtime moderation fires a call per
-- batch, and rebuilding the credentials and the service object every time is
-- pure overhead. The connection itself is reused across requests through the
-- keepalive pool.
local function get_comprehend_client(conf, ctx)
    if ctx.aws_cm_client then
        return ctx.aws_cm_client, ctx.aws_cm_endpoint
    end

    local comprehend = conf.comprehend

    if not aws_instance then
        aws_instance = aws()
    end
    local credentials = aws_instance:Credentials({
        accessKeyId = comprehend.access_key_id,
        secretAccessKey = comprehend.secret_access_key,
        sessionToken = comprehend.session_token,
    })

    local default_endpoint = "https://comprehend." .. comprehend.region .. ".amazonaws.com"
    local scheme, host, port = unpack(http:parse_uri(comprehend.endpoint or default_endpoint))
    local endpoint = scheme .. "://" .. host
    aws_instance.config.endpoint = endpoint
    aws_instance.config.ssl_verify = comprehend.ssl_verify

    ctx.aws_cm_client = aws_instance:Comprehend({
        credentials = credentials,
        endpoint = endpoint,
        region = comprehend.region,
        port = port,
        timeout = conf.timeout,
        keepalive_idle_timeout = conf.keepalive and conf.keepalive_timeout or nil,
    })
    ctx.aws_cm_endpoint = endpoint
    return ctx.aws_cm_client, endpoint
end


-- Last byte of the segment starting at `from`: at most `limit` bytes, cut on a
-- UTF-8 character boundary so a multibyte character is never torn in half.
local function segment_end(content, from, limit)
    local last = from + limit - 1
    if last >= #content then
        return #content
    end

    -- 0x80..0xBF are continuation bytes: walk back to the start of the
    -- character straddling the cut and end the segment just before it
    local cut = last
    for _ = 1, 3 do
        local byte = str_byte(content, cut + 1)
        if byte < 0x80 or byte >= 0xC0 then
            break
        end
        cut = cut - 1
    end

    local byte = str_byte(content, cut + 1)
    if cut < from or (byte >= 0x80 and byte < 0xC0) then
        -- one character wider than the limit, or invalid UTF-8: cut on the byte
        return last
    end
    return cut
end


-- Collect the next batch of text segments starting at `cursor`, staying within
-- Comprehend's per-segment, per-list and per-call size limits.
-- Returns the segments and the cursor to resume from.
local function next_batch(content, cursor, limit)
    local segments = {}
    local bytes = 0

    while cursor <= #content and #segments < MAX_SEGMENTS_PER_CALL do
        local stop = segment_end(content, cursor, limit)
        local piece = str_sub(content, cursor, stop)
        if #segments > 0 and bytes + #piece > MAX_CALL_BYTES then
            break
        end
        segments[#segments + 1] = { Text = piece }
        bytes = bytes + #piece
        cursor = stop + 1
    end

    return segments, cursor
end


-- Score one batch of segments. Returns the deny reason when a
-- category/toxicity threshold is exceeded, (nil, err) on a service error.
local function detect_batch(conf, ctx, segments, subject)
    local client, endpoint = get_comprehend_client(conf, ctx)
    local res, err = client:detectToxicContent({
        LanguageCode = "en",
        TextSegments = segments,
    })
    if not res then
        return nil, "failed to send request to " .. endpoint .. ": " .. err
    end

    local results = res.body and res.body.ResultList
    if type(results) ~= "table" or core.table.isempty(results) then
        return nil, "failed to get moderation results from response"
    end

    for _, result in ipairs(results) do
        if conf.moderation_categories then
            for _, item in pairs(result.Labels) do
                local threshold = conf.moderation_categories[item.Name]
                if threshold and item.Score > threshold then
                    return subject .. " exceeds " .. item.Name .. " threshold"
                end
            end
        end

        if result.Toxicity > conf.moderation_threshold then
            return subject .. " exceeds toxicity threshold"
        end
    end
end


-- Score content with AWS Comprehend detectToxicContent, splitting it into
-- segments the service accepts and batching those into as few calls as
-- possible. `subject` names the moderated text in the deny reason
-- ("request"/"response" body). Returns (reason, nil) when a category/toxicity
-- threshold is exceeded, (nil, err) on a service error, and (nil, nil) when
-- the content is clean.
local function detect_toxic(conf, ctx, content, subject, length_limit)
    local cursor = 1
    while cursor <= #content do
        local segments
        segments, cursor = next_batch(content, cursor, length_limit)

        local reason, err = detect_batch(conf, ctx, segments, subject)
        if err then
            return nil, err
        end
        if reason then
            set_risk_level(ctx, true)
            return reason
        end
    end

    set_risk_level(ctx, false)
end


-- Build a provider-compatible deny body so the AI client isn't broken.
local function build_deny_message(ctx, conf, reason)
    local message = conf.deny_message or reason
    local proto = protocols.get(ctx.ai_client_protocol)
    if not proto then
        return message
    end
    local stream = ctx.var.request_type == "ai_stream"
    local usage = ctx.llm_raw_usage
        or (proto.empty_usage and proto.empty_usage())
        or { prompt_tokens = 0, completion_tokens = 0, total_tokens = 0 }
    return proto.build_deny_response({
        text = message,
        model = ctx.var.request_llm_model,
        usage = usage,
        stream = stream,
    })
end


-- Moderate a piece of LLM response text.
-- Returns (deny_code, deny_body) on a hit, (nil, nil, err) on a Comprehend
-- failure, and nothing when the content is clean. The buffered caller fails
-- closed on err (bytes not sent yet, same as the request side); streaming
-- callers can't and let the content through.
local function moderate_response(ctx, conf, content)
    if not content or content == "" then
        -- nothing to score, but keep the risk_level contract satisfied so the
        -- streamed annotation still reports a verdict
        set_risk_level(ctx, false)
        ctx.aws_cm_response_scored = true
        return
    end

    local reason, err = detect_toxic(conf, ctx, content, "response body",
                                     conf.response_check_length_limit)
    if err then
        core.log.error(err)
        return nil, nil, err
    end
    ctx.aws_cm_response_scored = true
    if reason then
        return conf.deny_code, build_deny_message(ctx, conf, reason)
    end
end


-- Annotate a streamed chunk with the verdict from the assembled response.
-- The content already reached the client, so all we can do is tag it.
local function annotate_stream(ctx, body)
    local proto = protocols.get(ctx.ai_client_protocol)
    if not proto or not proto.is_data_event then
        return
    end

    -- Comprehend failed, so there is no verdict for this response. Leaving
    -- risk_level off is the honest outcome: annotating would report the
    -- request-side verdict, or a stale one, as if the response was scored.
    local scored = ctx.aws_cm_response_scored
    if not scored then
        core.log.warn("response was not scored, streaming without a risk_level annotation")
    end

    local events = sse.decode(body)
    local raw_events = {}
    local contains_done_event = false
    for _, event in ipairs(events) do
        if scored and proto.is_data_event(event) then
            local data, err = core.json.decode(event.data)
            -- a scalar or cjson.null decode can't be indexed; only annotate
            -- well-formed JSON object frames and leave anything else untouched
            if type(data) == "table" then
                data.risk_level = ctx.var.llm_content_risk_level
                event.data = core.json.encode(data)
            else
                core.log.warn("failed to decode SSE data as object: ", err or event.data)
            end
        end
        if proto.is_done_event and proto.is_done_event(event) then
            contains_done_event = true
        end
        table.insert(raw_events, sse.encode(event))
    end

    if not contains_done_event and proto.build_done_event and ctx.var.llm_request_done then
        table.insert(raw_events, proto.build_done_event())
    end
    return table.concat(raw_events)
end


function _M.access(conf, ctx)
    if not ctx.picked_ai_instance then
        local handled, code, body = binding.on_unsupported(
            conf.fail_mode, _M.name, ctx,
            "no ai instance picked (request did not pass through ai-proxy/ai-proxy-multi)",
            HTTP_INTERNAL_SERVER_ERROR, "no ai instance picked, " ..
                "ai-aws-content-moderation plugin must be used with " ..
                "ai-proxy or ai-proxy-multi plugin")
        if handled then
            return code, body
        end
        return
    end

    if not conf.check_request then
        core.log.info("skip request check for this request")
        return
    end

    local ct = core.request.header(ctx, "Content-Type")
    -- media types are case-insensitive, normalize before matching
    ct = ct and ct:lower()
    if ct and not core.string.has_prefix(ct, "application/json") then
        local handled, code, body = binding.on_unsupported(
            conf.fail_mode, _M.name, ctx,
            "unsupported content-type: " .. ct,
            HTTP_BAD_REQUEST, "unsupported content-type: " .. ct
                .. ", only application/json is supported")
        if handled then
            return code, body
        end
        return
    end

    local request_tab, err = core.request.get_json_request_body_table()
    if not request_tab then
        return HTTP_BAD_REQUEST, err
    end

    local proto = protocols.get(ctx.ai_client_protocol)
    if not proto or not proto.extract_request_content then
        local handled, code, body = binding.on_unsupported(
            conf.fail_mode, _M.name, ctx,
            "unsupported protocol: " .. (ctx.ai_client_protocol or "unknown"),
            HTTP_INTERNAL_SERVER_ERROR,
            "unsupported protocol: " .. (ctx.ai_client_protocol or "unknown"))
        if handled then
            return code, body
        end
        return
    end

    local contents = proto.extract_request_content(request_tab)
    local content = table.concat(contents, " ")
    if content == "" then
        return
    end

    local reason, err = detect_toxic(conf, ctx, content, "request body",
                                     conf.request_check_length_limit)
    if err then
        core.log.error(err)
        return HTTP_INTERNAL_SERVER_ERROR, err
    end
    if reason then
        local stream = ctx.var.request_type == "ai_stream"
        if stream then
            core.response.set_header("Content-Type", "text/event-stream")
        else
            core.response.set_header("Content-Type", "application/json")
        end
        return conf.deny_code, build_deny_message(ctx, conf, reason)
    end
end


function _M.lua_body_filter(conf, ctx, headers, body)
    if not conf.check_response then
        core.log.info("skip response check for this request")
        return
    end

    if ngx.status >= 400 then
        core.log.info("skip response check because upstream returned error status: ", ngx.status)
        return
    end

    local request_type = ctx.var.request_type

    -- ai-proxy hands us the fully assembled completion, so one check covers it.
    if request_type == "ai_chat" then
        local code, body, err = moderate_response(ctx, conf, ctx.var.llm_response_text)
        if err then
            -- the buffered body has not reached the client yet, so fail closed
            -- like the request side instead of shipping unmoderated content
            return HTTP_INTERNAL_SERVER_ERROR, err
        end
        return code, body
    end

    if request_type ~= "ai_stream" then
        return
    end

    if conf.stream_check_mode == "final_packet" then
        -- llm_response_text only appears once the stream is assembled, so
        -- earlier chunks pass through untouched.
        if not ctx.var.llm_response_text then
            return
        end
        if not ctx.aws_cm_response_moderated then
            ctx.aws_cm_response_moderated = true
            moderate_response(ctx, conf, ctx.var.llm_response_text)
        end
        return nil, annotate_stream(ctx, body)
    end

    -- realtime: moderate batches as they arrive so a hit can cut the stream off
    ctx.aws_cm_cache = ctx.aws_cm_cache or ""
    ctx.aws_cm_cache = ctx.aws_cm_cache
                       .. table.concat(ctx.llm_response_contents_in_chunk or {}, "")
    local now = ngx.now()
    ctx.aws_cm_last_check = ctx.aws_cm_last_check or now
    if #ctx.aws_cm_cache < conf.stream_check_cache_size
            and now - ctx.aws_cm_last_check < conf.stream_check_interval
            and not ctx.var.llm_request_done then
        return
    end

    ctx.aws_cm_last_check = now
    -- headers are already sent, so the deny body replaces the rest of the
    -- stream rather than changing the status code
    local _, message = moderate_response(ctx, conf, ctx.aws_cm_cache)
    if message then
        return ngx_ok, message
    end
    ctx.aws_cm_cache = ""
end

return _M
