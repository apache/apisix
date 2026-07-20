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

local ngx = ngx
local ngx_now = ngx.now
local core = require("apisix.core")
local require = require
local pcall   = pcall
local pairs   = pairs
local type    = type
local table   = table
local exporter = require("apisix.plugins.prometheus.exporter")
local protocols = require("apisix.plugins.ai-protocols")
local transport_http = require("apisix.plugins.ai-transport.http")
local log_sanitize = require("apisix.utils.log-sanitize")
local apisix_upstream = require("resty.apisix.upstream")

local _M = {}


-- Count tools in the final upstream request body.
-- OpenAI Chat/Responses: body.tools array
-- Anthropic Messages: body.tools array
local function count_request_tools(body)
    if type(body) ~= "table" then
        return 0
    end
    local tools = body.tools
    if type(tools) == "table" then
        return #tools
    end
    return 0
end


local function resolve_cap(cap_entry, key, conf, ctx)
    local val = cap_entry and cap_entry[key]
    if type(val) == "function" then
        return val(conf, ctx)
    end
    return val
end


-- Read the upstream error response body (429/5xx) so the provider's error
-- details are not discarded: they are logged on fallback and returned to the
-- client when no retry happens. Error bodies are small, so a single read_body()
-- is enough. Sets res._upstream_bytes for upstream-state accounting.
local function read_upstream_error_body(res)
    local body, err = res:read_body()
    if not body then
        core.log.warn("failed to read upstream error response body: ", err)
        return nil
    end
    res._upstream_bytes = #body
    return body
end

function _M.set_logging(ctx, summaries, payloads)
    if summaries then
        ctx.llm_summary = {
            request_model = ctx.var.request_llm_model,
            model = ctx.var.llm_model,
            duration = ctx.var.llm_time_to_first_token,
            prompt_tokens = ctx.var.llm_prompt_tokens,
            completion_tokens = ctx.var.llm_completion_tokens,
            total_tokens = ctx.var.llm_total_tokens,
            upstream_response_time = ctx.var.apisix_upstream_response_time,
            stream = ctx.var.llm_stream,
            tool_count = ctx.var.llm_tool_count,
            has_tool_calls = ctx.var.llm_has_tool_calls,
            end_user_id = ctx.var.llm_end_user_id,
            cache_read_input_tokens = ctx.var.llm_cache_read_input_tokens,
            cache_creation_input_tokens = ctx.var.llm_cache_creation_input_tokens,
            reasoning_tokens = ctx.var.llm_reasoning_tokens,
            content_risk_level = ctx.var.llm_content_risk_level,
        }
    end
    if payloads then
        local request_body = ctx.var.llm_request_body
        ctx.llm_request = {
            messages = protocols.get_request_content(request_body, ctx),
            stream = ctx.var.request_type == "ai_stream"
        }
        ctx.llm_response_text = {
            content = ctx.var.llm_response_text
        }
    end
end

-- Detect client protocol and stream mode early in access phase,
-- so that plugins with lower priority can use ctx.ai_client_protocol
-- and ctx.var.request_type before before_proxy runs.
function _M.detect_request_type(ctx, max_req_body_size)
    local ct = core.request.header(ctx, "Content-Type") or "application/json"
    if not core.string.has_prefix(ct, "application/json") then
        return "unsupported content-type: " .. ct
            .. ", only application/json is supported"
    end

    local body, err = core.request.get_json_request_body_table(max_req_body_size)
    if not body then
        -- get_json_request_body_table wraps the underlying error as {message=...}.
        -- An oversized body must surface as 413; all other read/parse failures
        -- stay 400 (caller default).
        local msg = type(err) == "table" and err.message or err
        if type(msg) == "string"
           and core.string.find(msg, "greater than the maximum size", 1, true) then
            core.log.error("failed to read request body: ", msg)
            return err, 413
        end
        return err
    end

    -- Extract model early so content moderation plugins can access it
    if body.model then
        ctx.var.request_llm_model = body.model
    end

    local protocol_name = protocols.detect(body, ctx)
    if not protocol_name then
        return "no matching AI protocol for the request"
    end

    ctx.ai_client_protocol = protocol_name

    local proto = protocols.get(protocol_name)
    if proto and proto.is_streaming(body) then
        ctx.var.request_type = "ai_stream"
    else
        ctx.var.request_type = "ai_chat"
    end
end


-- Execute the AI proxy pipeline:
--   1. Validate request
--   2. Route client protocol to driver capability (passthrough / convert / error)
--   3. Extract model from request body
--   4. Build HTTP request (protocol conversion, target protocol params, auth, headers)
--   5. Send via transport
--   6. Parse response (streaming or non-streaming)
--   7. Set keepalive
--
-- when on_error function is passed, before_proxy will keep on retrying until
-- on_error returns abort code
function _M.before_proxy(conf, ctx, on_error)
    while true do
        local ai_instance = ctx.picked_ai_instance

        local ai_provider = require("apisix.plugins.ai-providers." .. ai_instance.provider)

        local request_body, err = core.request.get_json_request_body_table()
        if not request_body then
            return 400, err
        end

        local extra_opts = {
            name = ai_instance.name,
            endpoint = ai_instance._resolved_endpoint
                       or core.table.try_read_attr(ai_instance, "override", "endpoint"),
            model_options = ai_instance.options,
            conf = ai_instance.provider_conf or {},
            auth = ai_instance.auth,
            host_header = ai_instance._resolved_host_header,
            ssl_server_name = ai_instance._resolved_ssl_server_name,
            override_llm_options =
                core.table.try_read_attr(ai_instance, "override", "llm_options"),
            request_body_override_map =
                core.table.try_read_attr(ai_instance, "override", "request_body"),
            request_body_force_override =
                core.table.try_read_attr(ai_instance, "override", "request_body_force_override"),
        }
        -- Step 1: Route client protocol to driver capability
        local client_protocol = ctx.ai_client_protocol
        local client_proto = protocols.get(client_protocol)
        local caps = ai_provider.capabilities or {}
        local provider_conf = extra_opts.conf
        local converter, target_proto
        local target_path, target_host

        if caps[client_protocol] then
            -- Provider natively supports this protocol — passthrough
            converter = nil
            target_proto = client_protocol
        elseif client_protocol == "passthrough" then
            -- Catch-all: proxy to the original request URI path
            converter = nil
            target_proto = "passthrough"
            target_path = ctx.var.uri
        else
            -- Find a converter to bridge the gap
            local conv, target_protocol = protocols.find_converter(client_protocol, caps)
            if not conv then
                local supported = {}
                for p in pairs(caps) do
                    supported[#supported + 1] = p
                end
                return 400, "provider " .. ai_instance.provider
                    .. " does not support " .. client_protocol
                    .. " protocol (supported: " .. table.concat(supported, ", ") .. ")"
            else
                converter = conv
            end
            target_proto = target_protocol
        end
        ctx.ai_converter = converter
        ctx.ai_target_protocol = target_proto
        local target_proto_module = protocols.get(target_proto)

        -- Step 2: Extract model from request
        local request_model = request_body.model

        if request_model then
            ctx.var.request_llm_model = request_model
        end
        local model = ai_instance.options and ai_instance.options.model or request_model
        if model then
            ctx.var.llm_model = model
        end

        target_path = target_path or resolve_cap(caps[target_proto], "path",
                                                  provider_conf, ctx)
        target_host = resolve_cap(caps[target_proto], "host",
                                  provider_conf, ctx)

        extra_opts.target_path = target_path
        extra_opts.target_host = target_host
        extra_opts.target_protocol = target_proto
        -- The transport is a pure client, so everything below that depends on the
        -- downstream request or on ctx is resolved here and handed over via
        -- extra_opts.
        extra_opts.header_transform = converter and converter.convert_headers

        -- ai-proxy is a transparent proxy of an inbound request, so it hands the
        -- provider everything taken from that request under one `downstream` key.
        -- Internal callers omit it entirely and thus forward nothing of the
        -- client's -- see ai-providers/base.lua build_request.
        local downstream = { headers = core.request.headers(ctx) }
        extra_opts.downstream = downstream

        -- passthrough proxies the client's method and query string verbatim.
        if target_proto == "passthrough" then
            downstream.method = core.request.get_method()
            local client_args = ctx.var.args and core.string.decode_args(ctx.var.args)
            if type(client_args) == "table" then
                downstream.args = client_args
            end
        end

        local do_request = function()
            ctx.llm_request_start_time = ngx.now()
            ctx.var.llm_request_body = request_body

            -- Step 2.5: protocol conversion. It runs in the provider's stead --
            -- converters stash state on ctx for the response side to read back --
            -- but stays inside do_request so the pcall below still bounds it: a
            -- converter fed hostile-but-valid JSON can raise (e.g. an Anthropic
            -- image block whose "source" is not an object).
            local body_for_llm = request_body
            local converted = false
            if converter and converter.convert_request then
                local new_body, conv_err = converter.convert_request(request_body, ctx)
                if not new_body then
                    return 400, {error_msg = conv_err or "invalid protocol"}
                end
                body_for_llm = new_body
                converted = true
            end

            -- Step 3: shape the body for the target protocol, then decide which
            -- bytes actually go out. When nothing has touched the body -- no
            -- conversion above, no shaping just now, and no earlier plugin rewrite
            -- (ai-request-rewrite marks that on ctx) -- the client's verbatim bytes
            -- are reused, keeping a pure passthrough byte-identical.
            local body, shaped = ai_provider:build_body(body_for_llm, extra_opts)
            if not shaped and not converted and not ctx.ai_request_body_changed then
                local raw = core.request.get_body()
                if type(raw) == "string" then
                    body = raw
                end
            end

            -- Step 4: assemble the HTTP request
            local params, build_err, code = ai_provider:build_request(
                conf, body, extra_opts)
            if not params then
                local body = {error_msg = build_err}
                if code then
                    return code, body
                end
                core.log.error("failed to build request: ", build_err)
                return 500, body
            end

            -- Compute built-in AI log fields from the final upstream request
            local final_body = params.body
            local is_stream = ctx.var.request_type == "ai_stream"
            ctx.var.llm_stream = is_stream and "true" or "false"
            ctx.var.llm_tool_count = count_request_tools(final_body)
            if target_proto_module and target_proto_module.extract_end_user_id then
                local end_user = target_proto_module.extract_end_user_id(final_body)
                if end_user then
                    ctx.var.llm_end_user_id = end_user
                end
            end

            core.log.info("sending request to LLM server: ",
                          core.json.delay_encode(log_sanitize.redact_params(params), true))

            -- Step 4: Send via transport
            local res, transport_err, err_meta = transport_http.request(params, conf.timeout)
            if not res then
                core.log.warn("failed to send request to LLM server: ", transport_err)
                if err_meta then
                    apisix_upstream.push_upstream_state({
                        addr = err_meta.upstream_addr,
                        status = transport_http.handle_error(transport_err),
                        connect_time = err_meta.connect_time,
                    })
                    if err_meta.upstream_uri then
                        ctx.var.upstream_uri = err_meta.upstream_uri
                    end
                    if err_meta.upstream_host then
                        ctx.var.upstream_host = err_meta.upstream_host
                    end
                    if err_meta.upstream_scheme then
                        ctx.var.upstream_scheme = err_meta.upstream_scheme
                    end
                    if err_meta.t0 then
                        apisix_upstream.update_upstream_state({
                            response_time = (ngx_now() - err_meta.t0) * 1000,
                        })
                    end
                end
                return transport_http.handle_error(transport_err)
            end

            -- Upstream responded — populate upstream state for access log
            apisix_upstream.push_upstream_state({
                addr = res._upstream_addr,
                status = res.status,
                connect_time = res._connect_time,
                header_time = res._header_time,
            })
            if res._upstream_uri then
                ctx.var.upstream_uri = res._upstream_uri
            end
            if res._upstream_host then
                ctx.var.upstream_host = res._upstream_host
            end
            if res._upstream_scheme then
                ctx.var.upstream_scheme = res._upstream_scheme
            end

            -- Upstream responded — mark source before any early returns
            core.response.set_response_source(ctx, "upstream")

            if res.status == 429 or (res.status >= 500 and res.status < 600) then
                -- Read the upstream error body before closing so the provider's
                -- error details survive: logged on fallback (see retry_on_error)
                -- and returned to the client when no retry happens.
                local error_body = read_upstream_error_body(res)
                local content_type = res.headers["Content-Type"]
                if content_type then
                    core.response.set_header("Content-Type", content_type)
                end
                if res._t0 then
                    apisix_upstream.update_upstream_state({
                        response_time = (ngx_now() - res._t0) * 1000,
                        response_length = res._upstream_bytes or 0,
                    })
                end
                if res._httpc then
                    res._httpc:close()
                end
                return res.status, error_body
            end

            local body_reader = res.body_reader
            if not body_reader then
                core.log.warn("AI service sent no response body")
                if res._t0 then
                    apisix_upstream.update_upstream_state({
                        response_time = (ngx_now() - res._t0) * 1000,
                    })
                end
                if res._httpc then
                    res._httpc:close()
                end
                return 500
            end

            local content_type = res.headers["Content-Type"]
            core.response.set_header("Content-Type", content_type)

            -- Step 5: Parse response
            -- Streaming responses arrive with provider-specific framing
            -- content-types: SSE for OpenAI/Anthropic/etc., AWS EventStream
            -- binary frames for Bedrock ConverseStream. The framing module
            -- is selected inside parse_streaming_response via
            -- provider.streaming_framing.
            local code, body
            local is_streaming_resp = content_type and (
                core.string.find(content_type, "text/event-stream", 1, true) or
                core.string.find(content_type,
                                 "application/vnd.amazon.eventstream", 1, true)
            )
            if is_streaming_resp then
                if not target_proto_module then
                    core.log.error("no protocol module for streaming target: ", target_proto)
                    return 500
                end

                code, body = ai_provider:parse_streaming_response(
                    ctx, res, target_proto_module, converter, conf)
            else
                -- Non-streaming: parse_response sets all llm_* token/tool vars
                -- via the client protocol adapter.
                local _, parse_err, parse_status = ai_provider:parse_response(
                    ctx, res, client_proto, converter, conf)
                if parse_err then
                    code = parse_status or 500
                    body = parse_err
                end
            end

            -- Finalize upstream state with response_time after body is consumed
            if res._t0 then
                apisix_upstream.update_upstream_state({
                    response_time = (ngx_now() - res._t0) * 1000,
                    response_length = res._upstream_bytes or 0,
                })
            end

            if conf.keepalive then
                transport_http.set_keepalive(res, conf.keepalive_timeout, conf.keepalive_pool)
            end

            return code, body
        end

        exporter.inc_llm_active_connections(ctx)
        ctx.llm_active_connections_tracked = true
        local ok, code_or_err, body = pcall(do_request)
        if not ok then
            core.log.error("failed to send request to AI service: ", code_or_err)
            return 500
        end
        if code_or_err and on_error then
            local abort_code = on_error(ctx, conf, code_or_err, body)
            if abort_code then
                return abort_code, body
            end
        else
            return code_or_err, body
        end
    end
end


return _M
