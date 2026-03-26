--
-- anthropic-native.lua
-- A driver for the Anthropic Messages API native protocol (/v1/messages).
-- Handles Anthropic-specific SSE event types, response format, and token usage fields.
-- Compatible with any endpoint that speaks the native Anthropic protocol,
-- e.g. api.anthropic.com/v1/messages or api.deepseek.com/anthropic/v1/messages.
--
-- Differences from openai-base:
--   Request:  removes stream_options (not supported), adds anthropic-version header
--   Response: content[].text  (not choices[].message.content)
--   SSE text: event=content_block_delta, delta.type=text_delta, delta.text
--   SSE token: message_start -> input_tokens; message_delta -> output_tokens
--   SSE end:  event=message_stop  (no [DONE] sentinel)
--   Token fields: input_tokens / output_tokens  (not prompt_tokens / completion_tokens)
--

local _M = {}

local mt = { __index = _M }

local CONTENT_TYPE_JSON = "application/json"
local ANTHROPIC_VERSION = "2023-06-01"

local core    = require("apisix.core")
local plugin  = require("apisix.plugin")
local http    = require("resty.http")
local url     = require("socket.url")
local sse     = require("apisix.plugins.ai-drivers.sse")

local ngx       = ngx
local ngx_now   = ngx.now
local table     = table
local pairs     = pairs
local type      = type
local math      = math
local ipairs    = ipairs
local setmetatable = setmetatable
local str_lower = string.lower

local HTTP_INTERNAL_SERVER_ERROR = ngx.HTTP_INTERNAL_SERVER_ERROR
local HTTP_GATEWAY_TIMEOUT       = ngx.HTTP_GATEWAY_TIMEOUT


function _M.new(opt)
    return setmetatable(opt or {}, mt)
end


-- Validate incoming request (same as openai-base: must be JSON)
function _M.validate_request(ctx)
    local ct = core.request.header(ctx, "Content-Type") or CONTENT_TYPE_JSON
    if not core.string.has_prefix(ct, CONTENT_TYPE_JSON) then
        return nil, "unsupported content-type: " .. ct
    end
    local request_table, err = core.request.get_json_request_body_table()
    if not request_table then
        return nil, err
    end
    return request_table, nil
end


local function handle_error(err)
    if core.string.find(err, "timeout") then
        return HTTP_GATEWAY_TIMEOUT
    end
    return HTTP_INTERNAL_SERVER_ERROR
end


-- Build forward headers, injecting Anthropic-required headers.
-- Blacklist host/content-length; honour caller-supplied auth headers.
local function construct_forward_headers(ext_opts_headers, ctx)
    local blacklist = { "host", "content-length" }

    local opts_headers_lower = {}
    for k, v in pairs(ext_opts_headers or {}) do
        opts_headers_lower[str_lower(k)] = v
    end

    local headers = core.table.merge(core.request.headers(ctx), opts_headers_lower)
    headers["Content-Type"]       = CONTENT_TYPE_JSON
    -- Anthropic native protocol requires this version header
    if not headers["anthropic-version"] then
        headers["anthropic-version"] = ANTHROPIC_VERSION
    end

    for _, h in ipairs(blacklist) do
        headers[h] = nil
    end
    return headers
end


-- Extract text content from Anthropic non-streaming response.
-- Response shape: { content: [{type:"text", text:"..."}], usage: {input_tokens, output_tokens} }
local function extract_response_text(res_body)
    if type(res_body.content) ~= "table" then
        return ""
    end
    local parts = {}
    for _, block in ipairs(res_body.content) do
        if type(block) == "table" and block.type == "text" and type(block.text) == "string" then
            core.table.insert(parts, block.text)
        end
    end
    return table.concat(parts, "")
end


local function read_response(conf, ctx, res, response_filter)
    local body_reader = res.body_reader
    if not body_reader then
        core.log.warn("AI service sent no response body")
        return HTTP_INTERNAL_SERVER_ERROR
    end

    local content_type = res.headers["Content-Type"]
    core.response.set_header("Content-Type", content_type)

    -- ── Streaming path ────────────────────────────────────────────────────────
    if content_type and core.string.find(content_type, "text/event-stream") then
        local contents = {}
        while true do
            local chunk, err = body_reader()
            ctx.var.apisix_upstream_response_time =
                math.floor((ngx_now() - ctx.llm_request_start_time) * 1000)

            if err then
                core.log.warn("failed to read response chunk: ", err)
                return handle_error(err)
            end
            if not chunk then
                return  -- stream finished
            end

            local events = sse.decode(chunk)
            ctx.llm_response_contents_in_chunk = {}

            for _, event in ipairs(events) do
                -- Skip empty data and ping events
                if event.data == "" or event.type == "ping" then
                    goto CONTINUE
                end

                -- sse.lua maps "data: [DONE]" to type="done" — some Anthropic-compatible
                -- endpoints (e.g. DeepSeek) append this OpenAI sentinel after message_stop.
                -- Safe to ignore; we already handled stream completion via message_stop.
                if event.type == "done" then
                    goto CONTINUE
                end

                -- message_stop: stream is done (standard Anthropic end-of-stream event)
                if event.type == "message_stop" then
                    ctx.var.llm_request_done = true
                    goto CONTINUE
                end

                -- error event: log and surface to client
                -- e.g. {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}
                if event.type == "error" then
                    core.log.warn("received error event from anthropic stream: ", event.data)
                    goto CONTINUE
                end

                local data, decode_err = core.json.decode(event.data)
                if not data then
                    core.log.warn("failed to decode SSE data: ", decode_err)
                    goto CONTINUE
                end

                -- message_start: carries input_tokens in message.usage.
                -- NOTE: output_tokens here is a pre-allocated value (usually 1), NOT the final
                -- count. We only store input_tokens; output_tokens is finalised in message_delta.
                if event.type == "message_start" then
                    local usage = data.message and data.message.usage
                    if usage and type(usage) == "table" then
                        ctx.llm_raw_usage = ctx.llm_raw_usage or {}
                        ctx.llm_raw_usage.input_tokens = usage.input_tokens or 0
                    end
                    goto CONTINUE
                end

                -- content_block_delta: carries text chunks (text_delta) or tool input
                -- (input_json_delta). We only collect text_delta for llm_response_text.
                -- TTFT is recorded on the first text_delta (true "first token").
                if event.type == "content_block_delta" then
                    local delta = data.delta
                    if type(delta) == "table" and delta.type == "text_delta"
                            and type(delta.text) == "string" then
                        -- Record TTFT on first actual text token
                        if ctx.var.llm_time_to_first_token == "0" then
                            ctx.var.llm_time_to_first_token =
                                math.floor((ngx_now() - ctx.llm_request_start_time) * 1000)
                        end
                        core.table.insert(contents, delta.text)
                        core.table.insert(ctx.llm_response_contents_in_chunk, delta.text)
                    end
                    goto CONTINUE
                end

                -- message_delta: carries the final output_tokens count in usage.
                -- This is the authoritative token count for the completed response.
                if event.type == "message_delta" then
                    local usage = data.usage
                    if usage and type(usage) == "table" then
                        ctx.llm_raw_usage = ctx.llm_raw_usage or {}
                        ctx.llm_raw_usage.output_tokens = usage.output_tokens or 0
                        local u  = ctx.llm_raw_usage
                        local pt = u.input_tokens  or 0
                        local ct = u.output_tokens or 0
                        ctx.ai_token_usage = {
                            prompt_tokens     = pt,
                            completion_tokens = ct,
                            total_tokens      = pt + ct,
                        }
                        ctx.var.llm_prompt_tokens     = pt
                        ctx.var.llm_completion_tokens = ct
                        ctx.var.llm_response_text     = table.concat(contents, "")
                        core.log.warn("got token usage from ai service (anthropic-native): ",
                            core.json.delay_encode(ctx.ai_token_usage))
                    end
                    goto CONTINUE
                end

                -- content_block_start / content_block_stop / unknown: pass through silently
                ::CONTINUE::
            end

            plugin.lua_response_filter(ctx, res.headers, chunk)
        end
        return  -- streaming done
    end

    -- ── Non-streaming path ────────────────────────────────────────────────────
    local headers = res.headers
    local raw_res_body, err = res:read_body()
    if not raw_res_body then
        core.log.warn("failed to read response body: ", err)
        return handle_error(err)
    end

    ngx.status = res.status
    ctx.var.llm_time_to_first_token =
        math.floor((ngx_now() - ctx.llm_request_start_time) * 1000)
    ctx.var.apisix_upstream_response_time = ctx.var.llm_time_to_first_token

    local res_body, decode_err = core.json.decode(raw_res_body)
    if decode_err then
        core.log.warn("invalid response body from ai service: ", raw_res_body,
            " err: ", decode_err, ", token usage not available")
    else
        if response_filter then
            local resp = { headers = headers, body = res_body }
            local code, ferr = response_filter(conf, ctx, resp)
            if code then
                return code, ferr
            end
            if resp.body then
                local body, encode_err = core.json.encode(resp.body)
                if not body then
                    core.log.error("failed to encode response body: ", encode_err)
                    return 500
                end
                raw_res_body = body
                res_body     = resp.body
            end
            headers = resp.headers
        end

        -- Extract token usage: Anthropic uses input_tokens / output_tokens
        ctx.ai_token_usage = {}
        if type(res_body.usage) == "table" then
            ctx.llm_raw_usage = res_body.usage
            local pt = res_body.usage.input_tokens  or res_body.usage.prompt_tokens     or 0
            local ct = res_body.usage.output_tokens or res_body.usage.completion_tokens or 0
            ctx.ai_token_usage = {
                prompt_tokens     = pt,
                completion_tokens = ct,
                total_tokens      = res_body.usage.total_tokens or (pt + ct),
            }
            core.log.warn("got token usage from ai service (anthropic-native): ",
                core.json.delay_encode(ctx.ai_token_usage))
        end
        ctx.var.llm_prompt_tokens     = ctx.ai_token_usage.prompt_tokens     or 0
        ctx.var.llm_completion_tokens = ctx.ai_token_usage.completion_tokens or 0

        -- Extract response text from Anthropic content[] array
        ctx.var.llm_response_text = extract_response_text(res_body)
    end

    plugin.lua_response_filter(ctx, headers, raw_res_body)
end


function _M.request(self, ctx, conf, request_table, extra_opts)
    local httpc, err = http.new()
    if not httpc then
        core.log.error("failed to create http client: ", err)
        return HTTP_INTERNAL_SERVER_ERROR
    end
    httpc:set_timeout(conf.timeout)

    -- Anthropic native protocol does NOT support stream_options
    -- (that is an OpenAI extension); remove it to avoid upstream errors
    request_table.stream_options = nil

    local endpoint = extra_opts.endpoint
    local parsed_url
    if endpoint then
        parsed_url = url.parse(endpoint)
    end

    local scheme = parsed_url and parsed_url.scheme or "https"
    local host   = parsed_url and parsed_url.host   or self.host or "api.anthropic.com"
    local port   = parsed_url and parsed_url.port
    if not port then
        port = (scheme == "https") and 443 or 80
    end

    local auth         = extra_opts.auth or {}
    local query_params = auth.query or {}

    if type(parsed_url) == "table" and parsed_url.query and #parsed_url.query > 0 then
        local args_tab = core.string.decode_args(parsed_url.query)
        if type(args_tab) == "table" then
            core.table.merge(query_params, args_tab)
        end
    end

    local path    = (parsed_url and parsed_url.path) or self.path or "/v1/messages"
    local headers = construct_forward_headers(auth.header or {}, ctx)

    local params = {
        method          = "POST",
        scheme          = scheme,
        headers         = headers,
        ssl_verify      = conf.ssl_verify,
        path            = path,
        query           = query_params,
        host            = host,
        port            = port,
        ssl_server_name = parsed_url and parsed_url.host or host,
    }

    -- Apply model_options (e.g. override model name)
    if extra_opts.model_options then
        for opt, val in pairs(extra_opts.model_options) do
            request_table[opt] = val
        end
    end
    params.body = request_table

    if self.request_filter then
        local code, ferr = self.request_filter(extra_opts.conf, ctx, params)
        if code then
            return code, ferr
        end
    end

    core.log.info("sending request to LLM server (anthropic-native): ",
        core.json.delay_encode(params, true))

    local ok, conn_err = httpc:connect(params)
    if not ok then
        core.log.error("failed to connect to LLM server: ", conn_err)
        return handle_error(conn_err)
    end

    local req_json, encode_err = core.json.encode(params.body)
    if not req_json then
        return 500, "failed to encode request body: " .. (encode_err or "unknown error")
    end
    params.body = req_json

    local res, req_err = httpc:request(params)
    if not res then
        core.log.warn("failed to send request to LLM server: ", req_err)
        return handle_error(req_err)
    end

    if res.status == 429 or (res.status >= 500 and res.status < 600) then
        return res.status
    end

    local code, body = read_response(extra_opts.conf, ctx, res, self.response_filter)

    if conf.keepalive then
        local ok, ka_err = httpc:set_keepalive(conf.keepalive_timeout, conf.keepalive_pool)
        if not ok then
            core.log.warn("failed to keepalive connection: ", ka_err)
        end
    end

    return code, body
end


return _M
