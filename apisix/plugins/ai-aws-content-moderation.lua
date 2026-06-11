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

local core = require("apisix.core")
local binding = require("apisix.plugins.ai-protocols.binding")
local protocols = require("apisix.plugins.ai-protocols")
local aws = require("resty.aws")
local aws_instance

local http = require("resty.http")

local pairs = pairs
local unpack = unpack
local type = type
local ipairs = ipairs
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
        fail_mode = binding.schema_property("skip"),
    },
    encrypt_fields = { "comprehend.secret_access_key" },
    required = { "comprehend" },
}


local _M = {
    version  = 0.1,
    priority = 1050,
    name     = "ai-aws-content-moderation",
    schema   = schema,
}


function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end


function _M.rewrite(conf, ctx)
    -- Consumer-bound moderation may receive non-AI traffic (e.g. multipart/binary
    -- uploads) whose body can't be moderated as text. Govern that via fail_mode.
    local ct = core.request.header(ctx, "Content-Type")
    -- media types are case-insensitive, normalize before matching
    ct = ct and ct:lower()
    if ct and not core.string.has_prefix(ct, "application/json") then
        local handled, code, resp = binding.on_unsupported(
            conf.fail_mode, _M.name, ctx,
            "unsupported content-type: " .. ct,
            HTTP_BAD_REQUEST, "unsupported content-type: " .. ct
                .. ", only application/json is supported")
        if handled then
            return code, resp
        end
        return
    end

    local body, err = core.request.get_json_request_body_table()
    if not body then
        local msg = type(err) == "table" and err.message or err
        local handled, code, resp = binding.on_unsupported(
            conf.fail_mode, _M.name, ctx,
            "failed to parse request body: " .. (msg or "invalid JSON"),
            HTTP_BAD_REQUEST, err)
        if handled then
            return code, resp
        end
        return
    end

    -- The plugin runs before ai-proxy, so detect the client protocol here rather
    -- than relying on ctx.ai_client_protocol. "passthrough" is the catch-all for
    -- non-AI bodies, which carry no LLM content to moderate.
    local protocol_name = protocols.detect(body, ctx)
    local proto = protocol_name and protocols.get(protocol_name)
    if not proto or protocol_name == "passthrough" or not proto.extract_request_content then
        local handled, code, resp = binding.on_unsupported(
            conf.fail_mode, _M.name, ctx,
            "no supported AI protocol for the request",
            HTTP_BAD_REQUEST, "no supported AI protocol for the request")
        if handled then
            return code, resp
        end
        return
    end

    -- moderate the decoded LLM-visible content, not the raw JSON envelope
    local contents = proto.extract_request_content(body)
    local text = core.table.concat(contents, " ")
    if text == "" then
        -- no LLM-visible content to moderate
        return
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

    local comprehend = aws_instance:Comprehend({
        credentials = credentials,
        endpoint = endpoint,
        region = comprehend.region,
        port = port,
    })

    local res, err = comprehend:detectToxicContent({
        LanguageCode = "en",
        TextSegments = {{
            Text = text
        }},
    })

    if not res then
        core.log.error("failed to send request to ", endpoint, ": ", err)
        return HTTP_INTERNAL_SERVER_ERROR, err
    end

    local results = res.body and res.body.ResultList
    if type(results) ~= "table" or core.table.isempty(results) then
        return HTTP_INTERNAL_SERVER_ERROR, "failed to get moderation results from response"
    end

    for _, result in ipairs(results) do
        if conf.moderation_categories then
            for _, item in pairs(result.Labels) do
                if not conf.moderation_categories[item.Name] then
                    goto continue
                end
                if item.Score > conf.moderation_categories[item.Name] then
                    return HTTP_BAD_REQUEST, "request body exceeds " .. item.Name .. " threshold"
                end
                ::continue::
            end
        end

        if result.Toxicity > conf.moderation_threshold then
            return HTTP_BAD_REQUEST, "request body exceeds toxicity threshold"
        end
    end
end

return _M
