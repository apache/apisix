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
local table     = table
local string    = string
local url       = require("socket.url")
local utf8      = require("lua-utf8")
local core      = require("apisix.core")
local http      = require("resty.http")
local uuid      = require("resty.jit-uuid")
local ai_schema = require("apisix.plugins.ai-drivers.schema")

local sse       = require("apisix.plugins.ai-drivers.sse")

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
        check_request = {type = "boolean", default = true},
        check_response = {type = "boolean", default = false},
        request_check_service = {type = "string", minLength = 1, default = "llm_query_moderation"},
        request_check_length_limit = {type = "number", default = 2000},
        response_check_service = {type = "string", minLength = 1,
                                  default = "llm_response_moderation"},
        response_check_length_limit = {type = "number", default = 5000},
        risk_level_bar = {type = "string",
                          enum = {"none", "low", "medium", "high", "max"},
                          default = "high"},
        deny_code = {type = "number", default = 200},
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


-- openresty ngx.escape_uri don't escape some sub-delimis in rfc 3986 but aliyun do it,
-- in order to we can calculate same signature with aliyun, we need escape those chars manually
local sub_delims_rfc3986 = {
    ["!"] = "%%21",
    ["'"] = "%%27",
    ["%("] = "%%28",
    ["%)"] = "%%29",
    ["*"] = "%%2A",
}
local function url_encoding(raw_str)
    local encoded_str = ngx.escape_uri(raw_str)
    for k, v in pairs(sub_delims_rfc3986) do
        encoded_str = string.gsub(encoded_str, k, v)
    end
    return encoded_str
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

    local httpc = http.new()
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

    local body = ngx.encode_args(params)
    core.log.debug("text moderation request body: ", body)
    local res, err = httpc:request{
        method = "POST",
        body = body,
        path = "/",
        headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
        }
    }
    if not res then
        return nil, "failed to request: " .. err
    end
    local raw_res_body, err = res:read_body()
    if not raw_res_body then
        return nil, "failed to read response body: " .. err
    end
    if conf.keepalive then
        local ok, err = httpc:set_keepalive(conf.keepalive_timeout, conf.keepalive_pool)
        if not ok then
            core.log.warn("failed to keepalive connection: ", err)
        end
    end
    if res.status ~= 200 then
        return nil, "failed to request aliyun text moderation service, status: " .. res.status
                        .. ", x-acs-request-id: " .. (res.headers["x-acs-request-id"] or "")
                        .. ", body: " .. raw_res_body
    end

    core.log.debug("raw response: ", raw_res_body)
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
local function deny_message(provider, message, model, stream, usage)
    local content = message or "Your request violate our content policy."
    if ai_schema.is_openai_compatible_provider(provider) then
        if stream then
            local data = {
                id = uuid.generate_v4(),
                object = "chat.completion.chunk",
                model = model,
                choices = {
                    {
                        index = 0,
                        delta = {
                            content = content,
                        },
                        finish_reason = "stop"
                    }
                },
                usage = usage,
            }

            return "data: " .. core.json.encode(data) .. "\n\n" .. "data: [DONE]"
        else
            return core.json.encode({
                id = uuid.generate_v4(),
                object = "chat.completion",
                model = model,
                choices = {
                  {
                    index = 0,
                    message = {
                      role = "assistant",
                      content = content
                    },
                    finish_reason = "stop"
                  }
                },
                usage = usage,
              })
        end
    end

    core.log.error("unsupported provider: ", provider)
    return content
end


local function content_moderation(ctx, conf, provider, model, content, length_limit,
                                  stream, usage, service_name)
    core.log.debug("execute content moderation, content: ", content)
    if not ctx.session_id then
        ctx.session_id = uuid.generate_v4()
    end
    if #content <= length_limit then
        local hit, err = check_single_content(ctx, conf, content, service_name)
        if hit then
            return conf.deny_code, deny_message(provider, conf.deny_message or err,
                                                    model, stream, usage)
        end
        if err then
            core.log.error("failed to check content: ", err)
        end
        return
    end

    local index = 1
    while true do
        if index > #content then
            return
        end
        local hit, err = check_single_content(ctx, conf,
                                                utf8.sub(content, index, index + length_limit - 1),
                                                service_name)
        index = index + length_limit
        if hit then
            return conf.deny_code, deny_message(provider, conf.deny_message or err,
                                                    model, stream, usage)
        end
        if err then
            core.log.error("failed to check content: ", err)
        end
    end
end


local function request_content_moderation(ctx, conf, content, model)
    if not content or #content == 0 then
        return
    end
    local provider = ctx.picked_ai_instance.provider
    local stream = ctx.var.request_type == "ai_stream"
    return content_moderation(ctx, conf, provider, model, content, conf.request_check_length_limit,
                                stream, {
                                    prompt_tokens = 0,
                                    completion_tokens = 0,
                                    total_tokens = 0
                                }, conf.request_check_service)
end


local function response_content_moderation(ctx, conf, content)
    if not content or #content == 0 then
        return
    end
    local provider = ctx.picked_ai_instance.provider
    local model = ctx.var.request_llm_model or ctx.var.llm_model
    local stream = ctx.var.request_type == "ai_stream"
    local usage = ctx.var.llm_raw_usage
    return content_moderation(ctx, conf, provider, model, content,
                                conf.response_check_length_limit,
                                stream, usage, conf.response_check_service)
end

function _M.access(conf, ctx)
    if not ctx.picked_ai_instance then
        return 500, "no ai instance picked, " ..
                "ai-aliyun-content-moderation plugin must be used with " ..
                "ai-proxy or ai-proxy-multi plugin"
    end
    local provider = ctx.picked_ai_instance.provider
    if not conf.check_request then
        core.log.info("skip request check for this request")
        return
    end
    local ct = core.request.header(ctx, "Content-Type")
    if ct and not core.string.has_prefix(ct, "application/json") then
        return 400, "unsupported content-type: " .. ct .. ", only application/json is supported"
    end
    local request_tab, err = core.request.get_json_request_body_table()
    if not request_tab then
        return 400, err
    end
    local ok, err = core.schema.check(ai_schema.chat_request_schema[provider], request_tab)
    if not ok then
        return 400, "request format doesn't match schema: " .. err
    end

    core.log.info("current ai provider: ", provider)

    if ai_schema.is_openai_compatible_provider(provider) then
        local contents = {}
        for _, message in ipairs(request_tab.messages) do
            if message.content then
                core.table.insert(contents, message.content)
            end
        end
        local content_to_check = table.concat(contents, " ")
        local code, message = request_content_moderation(ctx, conf,
                                                        content_to_check, request_tab.model)
        if code then
            if request_tab.stream then
                core.response.set_header("Content-Type", "text/event-stream")
                return code, message
            else
                core.response.set_header("Content-Type", "application/json")
                return code, message
            end
        end
        return
    end
    return 500, "unsupported provider: " .. provider
end


function _M.lua_body_filter(conf, ctx, headers, body)
    if not conf.check_response then
        core.log.info("skip response check for this request")
        return
    end
    local request_type = ctx.var.request_type

    if request_type == "ai_chat" then
        local content = ctx.var.llm_response_text
        return response_content_moderation(ctx, conf, content)
    end

    if conf.stream_check_mode == "final_packet" then
        if not ctx.var.llm_response_text then
            return
        end
        response_content_moderation(ctx, conf, ctx.var.llm_response_text)
        local events = sse.decode(body)
        for _, event in ipairs(events) do
            if event.type == "message" then
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
            if event.type == "done" then
                contains_done_event = true
            end
            table.insert(raw_events, sse.encode(event))
        end
        if not contains_done_event then
            table.insert(raw_events, "data: [DONE]")
        end
        return ngx_ok, table.concat(raw_events, "\n")
    end

    if conf.stream_check_mode == "realtime" then
        ctx.content_moderation_cache = ctx.content_moderation_cache or ""
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
        if message then
            return ngx_ok, message
        end
        ctx.content_moderation_cache = "" -- reset cache
    end
end


return _M
