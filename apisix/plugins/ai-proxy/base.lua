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

local _M = {}


local function resolve_cap(cap_entry, key, conf, ctx)
    local val = cap_entry and cap_entry[key]
    if type(val) == "function" then
        return val(conf, ctx)
    end
    return val
end

function _M.set_logging(ctx, summaries, payloads)
    if summaries then
        ctx.llm_summary = {
            request_model = ctx.var.request_llm_model,
            model = ctx.var.llm_model,
            duration = ctx.var.llm_time_to_first_token,
            prompt_tokens = ctx.var.llm_prompt_tokens,
            completion_tokens = ctx.var.llm_completion_tokens,
            upstream_response_time = ctx.var.apisix_upstream_response_time,
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
function _M.detect_request_type(ctx)
    local ct = core.request.header(ctx, "Content-Type") or "application/json"
    if not core.string.has_prefix(ct, "application/json") then
        return "unsupported content-type: " .. ct
            .. ", only application/json is supported"
    end

    local body, err = core.request.get_json_request_body_table()
    if not body then
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
            endpoint = core.table.try_read_attr(ai_instance, "override", "endpoint"),
            model_options = ai_instance.options,
            conf = ai_instance.provider_conf or {},
            auth = ai_instance.auth,
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

        local do_request = function()
            ctx.llm_request_start_time = ngx.now()
            ctx.var.llm_request_body = request_body

            -- Step 3: Build HTTP request params
            local params, build_err, code = ai_provider:build_request(
                ctx, conf, request_body, extra_opts)
            if not params then
                local body = {error_msg = build_err}
                if code then
                    return code, body
                end
                core.log.error("failed to build request: ", build_err)
                return 500, body
            end

            core.log.info("sending request to LLM server: ",
                          core.json.delay_encode(log_sanitize.redact_params(params), true))

            -- Step 4: Send via transport
            local res, transport_err = transport_http.request(params, conf.timeout)
            if not res then
                core.log.warn("failed to send request to LLM server: ", transport_err)
                return transport_http.handle_error(transport_err)
            end

            -- Upstream responded — mark source before any early returns
            core.response.set_response_source(ctx, "upstream")

            if res.status == 429 or (res.status >= 500 and res.status < 600) then
                return res.status
            end

            local body_reader = res.body_reader
            if not body_reader then
                core.log.warn("AI service sent no response body")
                return 500
            end

            local content_type = res.headers["Content-Type"]
            core.response.set_header("Content-Type", content_type)

            -- Step 5: Parse response
            local code, body
            if content_type and core.string.find(content_type, "text/event-stream") then
                local target_proto_module = protocols.get(target_proto)
                if not target_proto_module then
                    core.log.error("no protocol module for streaming target: ", target_proto)
                    return 500
                end
                code, body = ai_provider:parse_streaming_response(
                    ctx, res, target_proto_module, converter, conf)
            else
                local _, parse_err, parse_status = ai_provider:parse_response(
                    ctx, res, client_proto, converter, conf)
                if parse_err then
                    code = parse_status or 500
                    body = parse_err
                end
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
            local abort_code = on_error(ctx, conf, code_or_err)
            if abort_code then
                return abort_code, body
            end
        else
            return code_or_err, body
        end
    end
end


return _M
