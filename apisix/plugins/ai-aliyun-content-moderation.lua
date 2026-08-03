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
local ngx       = ngx
local ngx_ok    = ngx.OK
local os        = os
local pairs     = pairs
local ipairs    = ipairs
local next      = next
local table     = table
local string    = string
local type      = type
local url       = require("socket.url")
local utf8      = require("lua-utf8")
local core      = require("apisix.core")
local http      = require("resty.http")
local uuid      = require("resty.jit-uuid")
local protocols = require("apisix.plugins.ai-protocols")
local binding   = require("apisix.plugins.ai-protocols.binding")
local sse       = require("apisix.plugins.ai-transport.sse")

local schema = {
    type = "object",
    properties = {
        stream_check_mode = {
            type = "string",
            enum = {"realtime", "final_packet"},
            default = "final_packet",
            description = [[
            realtime: batched checks during streaming | final_packet: append risk_level at end
            ]]
        },
        stream_check_cache_size = {
            type = "integer",
            minimum = 1,
            default = 128,
            description = "max characters per moderation batch in realtime mode"
        },
        stream_check_interval = {
            type = "number",
            minimum = 0.1,
            default = 3,
            description = "seconds between batch checks in realtime mode"
        },
        endpoint = {type = "string", minLength = 1},
        region_id = {type ="string", minLength = 1},
        access_key_id = {type = "string", minLength = 1},
        access_key_secret = {type ="string", minLength = 1},
        fail_mode = binding.schema_property("skip"),
        check_request = {type = "boolean", default = true},
        check_response = {type = "boolean", default = false},
        request_check_mode = {
            type = "string",
            enum = {"last", "all"},
            default = "last",
            description = [[
            which user/tool messages to moderate: last (only the latest consecutive
            block of selected-role messages) | all (every selected-role message).
            Does not apply to the system role, which is always checked.
            ]]
        },
        request_check_roles = {
            type = "array",
            items = {type = "string", enum = {"user", "tool", "system"}},
            minItems = 1,
            uniqueItems = true,
            default = {"user"},
            description = [[
            which message roles to moderate on the request side. user/tool follow
            request_check_mode; system is checked on every request because it can
            be poisoned by malicious ToolCall arguments. Note: tool-result
            moderation applies to OpenAI-compatible formats where the tool output
            is a distinct "tool" role/item; for Anthropic/Bedrock (tool results
            are nested blocks inside user messages) tool content is not extracted.
            ]]
        },
        request_check_service = {type = "string", minLength = 1, default = "llm_query_moderation"},
        request_check_length_limit = {type = "integer", minimum = 1, default = 2000},
        response_check_service = {type = "string", minLength = 1,
                                  default = "llm_response_moderation"},
        response_check_length_limit = {type = "integer", minimum = 1, default = 5000},
        risk_level_bar = {type = "string",
                          enum = {"none", "low", "medium", "high", "max"},
                          default = "high"},
        deny_code = {
            type = "integer",
            minimum = 200,
            maximum = 599,
            default = 200,
            description = "HTTP status returned on a deny. Defaults to 200 so the " ..
                          "provider-compatible refusal parses as a normal completion in " ..
                          "client SDKs; set a 4xx to surface denies as HTTP errors instead.",
        },
        deny_message = {type = "string"},
        timeout = {
            type = "integer",
            minimum = 1,
            default = 10000,
            description = "timeout in milliseconds",
        },
        keepalive_pool = {type = "integer", minimum = 1, default = 30},
        keepalive = {type = "boolean", default = true},
        keepalive_timeout = {type = "integer", minimum = 1000, default = 60000},
        ssl_verify = {type = "boolean", default = true },
    },
    encrypt_fields = {"access_key_secret"},
    required = { "endpoint", "region_id", "access_key_id", "access_key_secret" },
}


local _M = {
    version  = 0.1,
    priority = 1029,
    name     = "ai-aliyun-content-moderation",
    schema   = schema,
}


function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end


local function risk_level_to_int(risk_level)
    local risk_levels = {
        ["max"] = 4,
        ["high"] = 3,
        ["medium"] = 2,
        ["low"] = 1,
        ["none"] = 0
    }
    return risk_levels[risk_level] or -1
end


-- OpenResty's ngx.escape_uri doesn't escape some RFC 3986 sub-delimiters that aliyun does,
-- so to compute the same signature as aliyun we escape those characters manually.
-- A single JIT-compiled PCRE pass is ~20x faster than five Lua string.gsub passes over the
-- encoded text, which is the hottest per-chunk operation in the signing path.
local sub_delims_rfc3986 = {
    ["!"] = "%21",
    ["'"] = "%27",
    ["("] = "%28",
    [")"] = "%29",
    ["*"] = "%2A",
}
local function url_encoding(raw_str)
    return (ngx.re.gsub(ngx.escape_uri(raw_str), "[!'()*]", function(m)
        return sub_delims_rfc3986[m[0]]
    end, "jo"))
end


local function calculate_sign(params, secret)
    local params_arr = {}
    for k, v in pairs(params) do
        table.insert(params_arr, ngx.escape_uri(k) .. "=" .. url_encoding(v))
    end
    table.sort(params_arr)
    local canonical_str = table.concat(params_arr, "&")
    local str_to_sign = "POST&%2F&" .. ngx.escape_uri(canonical_str)
    core.log.debug("string to calculate signature: ", str_to_sign)
    return ngx.encode_base64(ngx.hmac_sha1(secret, str_to_sign))
end


local function check_single_content(ctx, conf, content, service_name)
    if type(content) ~= "string" or content:find("%S") == nil then
        return
    end

    local timestamp = os.date("!%Y-%m-%dT%TZ")
    local random_id = uuid.generate_v4()
    local params = {
        ["AccessKeyId"] = conf.access_key_id,
        ["Action"] = "TextModerationPlus",
        ["Format"] = "JSON",
        ["RegionId"] = conf.region_id,
        ["Service"] = service_name,
        ["ServiceParameters"] = core.json.encode({sessionId = ctx.session_id, content = content}),
        ["SignatureMethod"] = "HMAC-SHA1",
        ["SignatureNonce"] = random_id,
        ["SignatureVersion"] = "1.0",
        ["Timestamp"] = timestamp,
        ["Version"] = "2022-03-02",
    }
    params["Signature"] = calculate_sign(params, conf.access_key_secret .. "&")

    -- Reuse one httpc across all moderation calls of a request (realtime fires
    -- many): cached on ctx, returned to the keepalive pool once at request end.
    local httpc = conf.keepalive and ctx.aliyun_cm_httpc
    if not httpc then
        httpc = http.new()
        httpc:set_timeout(conf.timeout)
        local parsed_url = url.parse(conf.endpoint)
        local ok, err = httpc:connect({
            scheme = parsed_url and parsed_url.scheme or "https",
            host = parsed_url and parsed_url.host,
            port = parsed_url and parsed_url.port,
            ssl_verify = conf.ssl_verify,
            ssl_server_name = parsed_url and parsed_url.host,
            pool_size = conf.keepalive and conf.keepalive_pool,
        })
        if not ok then
            return nil, "failed to connect: " .. err
        end
        if conf.keepalive then
            ctx.aliyun_cm_httpc = httpc
        end
    end

    local body = ngx.encode_args(params)
    local res, err = httpc:request{
        method = "POST",
        body = body,
        path = "/",
        headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
        }
    }
    if not res then
        ctx.aliyun_cm_httpc = nil
        httpc:close()
        return nil, "failed to request: " .. err
    end
    local raw_res_body, err = res:read_body()
    if not raw_res_body then
        ctx.aliyun_cm_httpc = nil
        httpc:close()
        return nil, "failed to read response body: " .. err
    end
    if not conf.keepalive then
        httpc:close()
    end
    if res.status ~= 200 then
        return nil, "failed to request aliyun text moderation service, status: " .. res.status
                        .. ", x-acs-request-id: " .. (res.headers["x-acs-request-id"] or "")
                        .. ", body: " .. raw_res_body
    end

    local response, err = core.json.decode(raw_res_body)
    if not response then
        return nil, "failed to decode response, "
                        .. ", x-acs-request-id: " .. (res.headers["x-acs-request-id"] or "")
                        .. ", err" .. err .. ", body: " .. raw_res_body
    end

    local risk_level = response.Data and response.Data.RiskLevel
    if not risk_level then
        return nil, "failed to get risk level: " .. raw_res_body
    end
    ctx.var.llm_content_risk_level = risk_level
    if risk_level_to_int(risk_level) < risk_level_to_int(conf.risk_level_bar) then
        return false
    end
    -- answer is readable message for human
    return true, response.Data.Advice and response.Data.Advice[1]
                        and response.Data.Advice[1].Answer
end


-- we need to return a provider compatible response without broken the ai client
local function deny_message(ctx, message)
    local proto = protocols.get(ctx.ai_client_protocol)
    if not proto then
        core.log.error("unsupported protocol: ", ctx.ai_client_protocol)
        return message
    end
    local stream = ctx.var.request_type == "ai_stream"
    local model = ctx.var.request_llm_model
    local usage = ctx.llm_raw_usage
        or (proto.empty_usage and proto.empty_usage())
        or { prompt_tokens = 0, completion_tokens = 0, total_tokens = 0 }
    return proto.build_deny_response({
        text = message or "Your request violate our content policy.",
        model = model,
        usage = usage,
        stream = stream,
    })
end


local function release_cm_httpc(ctx, conf)
    local httpc = ctx.aliyun_cm_httpc
    if not httpc then
        return
    end
    ctx.aliyun_cm_httpc = nil
    local ok, err = httpc:set_keepalive(conf.keepalive_timeout, conf.keepalive_pool)
    if not ok then
        core.log.warn("failed to keepalive connection: ", err)
    end
end


local function content_moderation(ctx, conf, content, length_limit, service_name)
    if not ctx.session_id then
        ctx.session_id = uuid.generate_v4()
    end
    core.log.debug("execute content moderation")
    if #content <= length_limit then
        local hit, err = check_single_content(ctx, conf, content, service_name)
        if hit then
            return conf.deny_code, deny_message(ctx, conf.deny_message or err)
        end
        if err then
            core.log.error("failed to check content: ", err)
        end
        return
    end

    -- Walk the content with a byte cursor. utf8.offset(content, length_limit + 1,
    -- cur) returns the byte position length_limit characters ahead of cur,
    -- scanning only that window, so slicing with byte-based string.sub keeps the
    -- whole loop O(n). The previous utf8.sub(content, index, ...) located the
    -- index-th character by scanning from the string start on every chunk, which
    -- made large request/response bodies O(n^2).
    local cur = 1
    while cur <= #content do
        local next_byte = utf8.offset(content, length_limit + 1, cur)
        local piece = next_byte and string.sub(content, cur, next_byte - 1)
                                 or string.sub(content, cur)
        local hit, err = check_single_content(ctx, conf, piece, service_name)
        if hit then
            return conf.deny_code, deny_message(ctx, conf.deny_message or err)
        end
        if err then
            core.log.error("failed to check content: ", err)
        end
        if not next_byte then
            return
        end
        cur = next_byte
    end
end


local function request_content_moderation(ctx, conf, content)
    if not content or #content == 0 then
        return
    end
    return content_moderation(ctx, conf, content, conf.request_check_length_limit,
                                conf.request_check_service)
end


local function response_content_moderation(ctx, conf, content)
    if not content or #content == 0 then
        return
    end
    return content_moderation(ctx, conf, content,
                                conf.response_check_length_limit,
                                conf.response_check_service)
end


function _M.access(conf, ctx)
    if not ctx.picked_ai_instance then
        local handled, code, body = binding.on_unsupported(
            conf.fail_mode, _M.name, ctx,
            "no ai instance picked (request did not pass through ai-proxy/ai-proxy-multi)",
            500, "no ai instance picked, " ..
                "ai-aliyun-content-moderation plugin must be used with " ..
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
            400, "unsupported content-type: " .. ct
                .. ", only application/json is supported")
        if handled then
            return code, body
        end
        return
    end
    local request_tab, err = core.request.get_json_request_body_table()
    if not request_tab then
        return 400, err
    end

    local proto = protocols.get(ctx.ai_client_protocol)
    if not proto or not proto.extract_request_content then
        local handled, code, body = binding.on_unsupported(
            conf.fail_mode, _M.name, ctx,
            "unsupported protocol: " .. (ctx.ai_client_protocol or "unknown"),
            500, "unsupported protocol: " .. (ctx.ai_client_protocol or "unknown"))
        if handled then
            return code, body
        end
        return
    end

    local function set_deny_content_type()
        if ctx.var.request_type == "ai_stream" then
            core.response.set_header("Content-Type", "text/event-stream")
        else
            core.response.set_header("Content-Type", "application/json")
        end
    end

    local roles = {}
    for _, r in ipairs(conf.request_check_roles) do
        roles[r] = true
    end
    local turn_roles = {}
    if roles.user then turn_roles.user = true end
    if roles.tool then turn_roles.tool = true end

    -- A configured role whose extractor this protocol doesn't implement would
    -- otherwise pass unmoderated. Route that through fail_mode instead of
    -- silently skipping the configured moderation.
    if (roles.system and not proto.extract_system_content)
            or (next(turn_roles) and not proto.extract_turn_content) then
        local handled, code, body = binding.on_unsupported(
            conf.fail_mode, _M.name, ctx,
            "protocol cannot extract configured request_check_roles",
            500, "protocol " .. (ctx.ai_client_protocol or "unknown")
                .. " cannot moderate the configured request_check_roles")
        if handled then
            return code, body
        end
        return
    end

    -- Collect the text to moderate from all configured roles and send it in a
    -- single request. The Aliyun service takes a flat `content` string with no
    -- role field, so there is nothing to gain from separate per-role calls.
    -- system is always included (every request, not subject to request_check_mode,
    -- because it can be poisoned by malicious ToolCall arguments); user/tool
    -- follow request_check_mode ("last" = latest turn, "all" = every message).
    local contents = {}
    if roles.system then
        local system_texts = proto.extract_system_content(request_tab)
        for i = 1, #system_texts do
            contents[#contents + 1] = system_texts[i]
        end
    end
    if next(turn_roles) then
        local turn_texts = proto.extract_turn_content(request_tab,
                                                      conf.request_check_mode, turn_roles)
        for i = 1, #turn_texts do
            contents[#contents + 1] = turn_texts[i]
        end
    end
    local content_to_check = table.concat(contents, " ")

    local code, message = request_content_moderation(ctx, conf, content_to_check)
    release_cm_httpc(ctx, conf)
    if code then
        set_deny_content_type()
        return code, message
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

    if request_type == "ai_chat" then
        local content = ctx.var.llm_response_text
        local code, message = response_content_moderation(ctx, conf, content)
        release_cm_httpc(ctx, conf)
        return code, message
    end

    local proto = protocols.get(ctx.ai_client_protocol)

    if conf.stream_check_mode == "final_packet" then
        if not ctx.var.llm_response_text then
            return
        end
        if not ctx.ai_aliyun_response_moderated then
            response_content_moderation(ctx, conf, ctx.var.llm_response_text)
            release_cm_httpc(ctx, conf)
            ctx.ai_aliyun_response_moderated = true
        end
        local events = sse.decode(body)
        for _, event in ipairs(events) do
            if proto and proto.is_data_event(event) then
                local data, err = core.json.decode(event.data)
                if not data then
                    core.log.warn("failed to decode SSE data: ", err)
                    goto CONTINUE
                end
                data.risk_level = ctx.var.llm_content_risk_level
                event.data = core.json.encode(data)
            end
            ::CONTINUE::
        end

        local raw_events = {}
        local contains_done_event = false
        for _, event in ipairs(events) do
            if proto and proto.is_done_event(event) then
                contains_done_event = true
            end
            table.insert(raw_events, sse.encode(event))
        end
        if not contains_done_event and proto and ctx.var.llm_request_done then
            table.insert(raw_events, proto.build_done_event())
        end
        return nil, table.concat(raw_events, "\n")
    end

    if conf.stream_check_mode == "realtime" then
        ctx.content_moderation_cache = ctx.content_moderation_cache or ""
        ctx.llm_response_contents_in_chunk = ctx.llm_response_contents_in_chunk or {}
        local content = table.concat(ctx.llm_response_contents_in_chunk, "")
        ctx.content_moderation_cache = ctx.content_moderation_cache .. content
        local now_time = ngx.now()
        ctx.last_moderate_time = ctx.last_moderate_time or now_time
        if #ctx.content_moderation_cache < conf.stream_check_cache_size
                and now_time - ctx.last_moderate_time < conf.stream_check_interval
                and not ctx.var.llm_request_done then
            return
        end
        ctx.last_moderate_time = now_time
        local _, message = response_content_moderation(ctx, conf, ctx.content_moderation_cache)
        if message or ctx.var.llm_request_done then
            release_cm_httpc(ctx, conf)
        end
        if message then
            return ngx_ok, message
        end
        ctx.content_moderation_cache = "" -- reset cache
    end
end


return _M
