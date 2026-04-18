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

--- AI provider base class.
-- Provides the request/response lifecycle shared by all AI providers.
-- Uses transport modules (http, sse, auth) for infrastructure concerns.

local _M = {}

local mt = {
    __index = _M
}

-- Maximum SSE buffer size per request (1 MB).
local MAX_SSE_BUF_SIZE = 1024 * 1024

local core = require("apisix.core")
local plugin = require("apisix.plugin")
local url  = require("socket.url")
local sse  = require("apisix.plugins.ai-transport.sse")
local transport_http = require("apisix.plugins.ai-transport.http")
local transport_auth = require("apisix.plugins.ai-transport.auth")
local log_sanitize = require("apisix.utils.log-sanitize")
local protocols = require("apisix.plugins.ai-protocols")
local deep_merge = require("apisix.plugins.ai-proxy.merge").deep_merge
local ngx = ngx
local ngx_now = ngx.now

local table = table
local pairs = pairs
local type  = type
local math  = math
local ipairs = ipairs
local setmetatable = setmetatable


function _M.new(opt)
    return setmetatable(opt, mt)
end


-- Merge usage fields into ctx, preserving earlier non-zero values.
-- Anthropic streams send usage across multiple SSE events (message_start has
-- input/cache tokens, message_delta has output tokens), so we merge rather
-- than overwrite to avoid losing fields from earlier events.
local function merge_usage(ctx, parsed)
    if not ctx.ai_token_usage then
        ctx.ai_token_usage = parsed.usage
    else
        for k, v in pairs(parsed.usage) do
            if type(v) == "number" and v > 0 then
                ctx.ai_token_usage[k] = v
            end
        end
    end

    local raw = parsed.raw_usage or parsed.usage
    if not ctx.llm_raw_usage then
        ctx.llm_raw_usage = raw
    else
        for k, v in pairs(raw) do
            if type(v) == "number" and v > 0 then
                ctx.llm_raw_usage[k] = v
            end
        end
    end
end


--- Build HTTP request parameters from driver config and extra_opts.
-- @return table params HTTP parameters ready for transport_http.request()
-- @return string|nil err Error message
function _M.build_request(self, ctx, conf, request_body, opts)
    -- Protocol conversion (when a converter bridges client→target protocol)
    local converter = ctx.ai_converter
    if converter and converter.convert_request then
        local converted, err = converter.convert_request(request_body, ctx)
        if not converted then
            return nil, err or "invalid protocol", 400
        end
        request_body = converted
    end

    -- Inject target-protocol-specific parameters (e.g. stream_options for OpenAI).
    -- This runs after conversion so it covers both passthrough and convert scenarios.
    local target_protocol = ctx.ai_target_protocol
    if target_protocol then
        local target_proto = protocols.get(target_protocol)
        if target_proto and target_proto.prepare_outgoing_request then
            target_proto.prepare_outgoing_request(request_body)
        end
    end

    core.log.info("request extra_opts to LLM server: ",
                  core.json.delay_encode(log_sanitize.redact_extra_opts(opts), true))

    -- Auth: GCP token
    local auth = opts.auth or {}
    local token
    if auth.gcp then
        local access_token, err = transport_auth.fetch_gcp_access_token(ctx, opts.name,
                                        auth.gcp)
        if not access_token then
            return nil, "failed to get gcp access token: " .. (err or "unknown")
        end
        token = access_token
    end

    -- Parse endpoint URL
    local endpoint = opts.endpoint
    local parsed_url
    if endpoint then
        parsed_url = url.parse(endpoint)
    end

    local scheme = parsed_url and parsed_url.scheme or "https"
    local host = parsed_url and parsed_url.host
                 or opts.target_host or self.host
    local port = parsed_url and parsed_url.port
    if not port then
        if scheme == "https" then
            port = 443
        else
            port = 80
        end
    end

    local query_params = auth.query and core.table.clone(auth.query) or {}

    if type(parsed_url) == "table" and parsed_url.query and #parsed_url.query > 0 then
        local args_tab = core.string.decode_args(parsed_url.query)
        if type(args_tab) == "table" then
            core.table.merge(query_params, args_tab)
        end
    end

    local path
    if parsed_url and parsed_url.path then
        path = parsed_url.path
    else
        path = opts.target_path
    end

    local headers = transport_http.construct_forward_headers(auth.header or {}, ctx)
    if token then
        headers["authorization"] = "Bearer " .. token
    end

    local params = {
        method = "POST",
        scheme = scheme,
        headers = headers,
        ssl_verify = conf.ssl_verify,
        path = path,
        query = query_params,
        host = host,
        port = port,
        ssl_server_name = parsed_url and parsed_url.host
                          or opts.target_host or self.host,
    }

    -- Inject model options (flat overwrite)
    if opts.model_options then
        for opt, val in pairs(opts.model_options) do
            if request_body[opt] ~= nil then
                core.log.info("model_options overwriting request field '", opt, "'")
            end
            request_body[opt] = val
        end
    end

    -- Inject per-target-protocol request body override (deep merge)
    if opts.request_body_override_map then
        local patch = opts.request_body_override_map[ctx.ai_target_protocol]
        if patch then
            core.log.info("applying request_body override for target protocol '",
                          ctx.ai_target_protocol, "'")
            request_body = deep_merge(request_body, patch,
                                      opts.request_body_force_override)
        end
    end
    params.body = request_body

    if self.remove_model then
        request_body.model = nil
    end

    return params
end


--- Parse a non-streaming response body.
-- Converts the response (if converter exists), then extracts usage/text
-- using the client protocol module.
-- @param client_proto table The protocol module for the client's protocol
-- @param converter table|nil The converter module (if protocol conversion needed)
-- @return table|nil Parsed and optionally converted response body
-- @return string|nil Error
function _M.parse_response(self, ctx, res, client_proto, converter)
    local headers = res.headers
    local raw_res_body, err = res:read_body()
    if not raw_res_body then
        core.log.warn("failed to read response body: ", err)
        return nil, err
    end
    ngx.status = res.status
    ctx.var.llm_time_to_first_token = math.floor((ngx_now() - ctx.llm_request_start_time) * 1000)
    ctx.var.apisix_upstream_response_time = ctx.var.llm_time_to_first_token

    local res_body, decode_err = core.json.decode(raw_res_body, { null_as_nil = true })
    if decode_err then
        core.log.warn("failed to decode response from ai service, err: ", decode_err,
            ", it will cause token usage not available")
        plugin.lua_response_filter(ctx, headers, raw_res_body)
        return nil
    end

    -- Convert response body to client format (converter works downstream of protocol)
    if converter and converter.convert_response then
        local new_body, conv_err = converter.convert_response(res_body, ctx)
        if not new_body and conv_err then
            core.log.error("failed to convert response: ", conv_err)
            return nil, conv_err
        end
        if new_body then
            res_body = new_body
            local raw, encode_err = core.json.encode(res_body)
            if not raw then
                core.log.error("failed to encode response body: ", encode_err)
                return nil, encode_err
            end
            raw_res_body = raw
        end
    end

    -- Extract usage and text using client protocol (works on client format)
    core.log.info("got token usage from ai service: ", core.json.delay_encode(res_body.usage))
    ctx.ai_token_usage = {}
    local usage, raw_usage = client_proto.extract_usage(res_body)
    if usage then
        ctx.llm_raw_usage = raw_usage
        ctx.ai_token_usage = usage
    end
    ctx.var.llm_prompt_tokens = ctx.ai_token_usage.prompt_tokens or 0
    ctx.var.llm_completion_tokens = ctx.ai_token_usage.completion_tokens or 0

    local response_text = client_proto.extract_response_text(res_body)
    if response_text then
        ctx.var.llm_response_text = response_text
    end

    plugin.lua_response_filter(ctx, headers, raw_res_body)
    return res_body
end


--- Process streaming SSE response.
-- Uses target protocol for SSE parsing and converter (if present) for
-- transforming events to client format.
-- @param target_proto table The protocol module for the provider's native protocol
-- @param converter table|nil The converter module (if protocol conversion needed)
function _M.parse_streaming_response(self, ctx, res, target_proto, converter)
    local body_reader = res.body_reader
    local contents = {}
    local sse_state = { is_first = true }
    local sse_buf = ""
    -- Track whether any output was sent to the client.
    -- When a converter is active but the upstream returns a different SSE format,
    -- all events may be skipped and no output produced, leaving the response
    -- uncommitted and causing nginx to fall through to the balancer phase.
    local output_sent = false

    while true do
        local chunk, err = body_reader()
        ctx.var.apisix_upstream_response_time = math.floor((ngx_now() -
                                         ctx.llm_request_start_time) * 1000)
        if err then
            core.log.warn("failed to read response chunk: ", err)
            return transport_http.handle_error(err)
        end
        if not chunk then
            if #sse_buf > 0 then
                core.log.warn("dropping incomplete SSE frame at EOF, size: ",
                              #sse_buf)
            end

            if converter and not output_sent then
                local msg = "streaming response completed without producing "
                            .. "any output; the upstream likely returned a "
                            .. "different SSE format than the converter expects"
                core.log.error(msg)
                return 502, msg
            end
            return
        end

        if ctx.var.llm_time_to_first_token == "0" then
            ctx.var.llm_time_to_first_token = math.floor(
                                            (ngx_now() - ctx.llm_request_start_time) * 1000)
        end

        sse_buf = sse_buf .. chunk
        local complete, remainder = sse.split_buf(sse_buf)
        if #remainder > MAX_SSE_BUF_SIZE then
            core.log.warn("SSE remainder exceeded ", MAX_SSE_BUF_SIZE, " bytes, resetting")
            remainder = ""
        end
        sse_buf = remainder
        local events = complete ~= "" and sse.decode(complete) or {}
        ctx.llm_response_contents_in_chunk = {}
        local converted_chunks = {}

        for _, event in ipairs(events) do
            -- Target protocol parses the provider's SSE format
            local parsed = target_proto.parse_sse_event(event, ctx, sse_state)
            if not parsed or parsed.type == "skip" then
                goto CONTINUE
            end

            -- Converter transforms parsed events to client format (downstream)
            if converter and converter.convert_sse_events then
                local converted = converter.convert_sse_events(parsed, ctx, sse_state)
                if converted then
                    for _, ce in ipairs(converted) do
                        table.insert(converted_chunks, sse.encode(ce))
                    end
                end
            end

            if parsed.texts then
                for _, text in ipairs(parsed.texts) do
                    core.table.insert(contents, text)
                    core.table.insert(ctx.llm_response_contents_in_chunk, text)
                end
            end

            if parsed.usage then
                core.log.info("got token usage from ai service: ",
                                    core.json.delay_encode(parsed.raw_usage or parsed.usage))
                merge_usage(ctx, parsed)
                ctx.var.llm_prompt_tokens = ctx.ai_token_usage.prompt_tokens
                ctx.var.llm_completion_tokens = ctx.ai_token_usage.completion_tokens
                ctx.var.llm_response_text = table.concat(contents, "")
            end

            if parsed.type == "done" or parsed.type == "usage_and_done" then
                ctx.var.llm_request_done = true
            end

            ::CONTINUE::
        end

        -- Output: converter events or passthrough raw chunk
        if converter then
            for _, c in ipairs(converted_chunks) do
                plugin.lua_response_filter(ctx, res.headers, c)
                output_sent = true
            end
        else
            plugin.lua_response_filter(ctx, res.headers, chunk)
        end
    end
end


--- Non-streaming LLM request client.
-- Sends a request to the LLM service and returns the raw response body.
-- Used by plugins that need to call an LLM as a sidecar (e.g., ai-request-rewrite).
-- Does NOT invoke protocol modules, plugin response filters, or SSE parsing.
-- @return number|nil HTTP status code
-- @return string|nil Raw response body (JSON string)
-- @return string|nil Error message
function _M.request(self, ctx, conf, request_table, extra_opts)
    local params, err = self:build_request(ctx, conf, request_table, extra_opts)
    if not params then
        core.log.error("failed to build request: ", err)
        return 500, nil, err
    end

    core.log.info("sending sidecar request to LLM server: ",
                  core.json.delay_encode(log_sanitize.redact_params(params), true))

    local res, req_err = transport_http.request(params, conf.timeout)
    if not res then
        core.log.warn("failed to send request to LLM server: ", req_err)
        return transport_http.handle_error(req_err), nil, req_err
    end

    local raw_body, read_err = res:read_body()

    if conf.keepalive then
        transport_http.set_keepalive(res, conf.keepalive_timeout, conf.keepalive_pool)
    end

    if not raw_body then
        return 500, nil, "failed to read response body: " .. (read_err or "")
    end

    return res.status, raw_body
end


return _M
