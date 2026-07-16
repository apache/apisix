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
local aws       = require("resty.aws")
local aws_instance

local http = require("resty.http")

local ngx     = ngx
local pairs   = pairs
local unpack  = unpack
local type    = type
local ipairs  = ipairs
local table   = table
local HTTP_INTERNAL_SERVER_ERROR = ngx.HTTP_INTERNAL_SERVER_ERROR
local HTTP_BAD_REQUEST = ngx.HTTP_BAD_REQUEST

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


-- Score content with AWS Comprehend detectToxicContent.
-- Returns (reason, nil) when a category/toxicity threshold is exceeded,
-- (nil, err) on a service error, and (nil, nil) when the content is clean.
local function detect_toxic(conf, content)
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

    local comprehend_client = aws_instance:Comprehend({
        credentials = credentials,
        endpoint = endpoint,
        region = comprehend.region,
        port = port,
    })

    local res, err = comprehend_client:detectToxicContent({
        LanguageCode = "en",
        TextSegments = {{
            Text = content
        }},
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
                    return "request body exceeds " .. item.Name .. " threshold"
                end
            end
        end

        if result.Toxicity > conf.moderation_threshold then
            return "request body exceeds toxicity threshold"
        end
    end
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

    local reason, err = detect_toxic(conf, content)
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

return _M
