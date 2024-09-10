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
local core = require("apisix.core")
local aws = require("resty.aws")
local http = require("resty.http")
local fetch_secrets = require("apisix.secret").fetch_secrets

local aws_instance = aws()
local next = next
local pairs = pairs
local unpack = unpack
local type = type
local ipairs = ipairs

local aws_comprehend_schema = {
    type = "object",
    properties = {
        access_key_id = { type = "string" },
        secret_access_key = { type = "string" },
        region = { type = "string" },
        endpoint = {
            type = "string",
            pattern = [[^https?://]]
        },
    },
    required = { "access_key_id", "secret_access_key", "region", }
}

local schema = {
    type = "object",
    properties = {
        provider = {
            type = "object",
            properties = {
                aws_comprehend = aws_comprehend_schema
            },
            -- change to oneOf/enum while implementing support for other services
            required = { "aws_comprehend" }
        },
        moderation_categories = {
            type = "object",
            patternProperties = {
                -- luacheck: push max code line length 300
                ["^(PROFANITY|HATE_SPEECH|INSULT|HARASSMENT_OR_ABUSE|SEXUAL|VIOLENCE_OR_THREAT)$"] = {
                -- luacheck: pop
                type = "number",
                    minimum = 0,
                    maximum = 1
                }
            },
            additionalProperties = false
        },
        toxicity_level = {
            type = "number",
            minimum = 0,
            maximum = 1,
            default = 0.5
        },
        type = {
            type = "string",
            enum = { "openai" },
        }
    },
    required = { "provider", "type" },
}


local _M = {
    version  = 0.1,
    priority = 1040, -- TODO: might change
    name     = "ai-content-moderation",
    schema   = schema,
}


function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end

function _M.rewrite(conf, ctx)
    conf = fetch_secrets(conf, true, conf, "")
    if not conf then
        return 500, "failed to retrieve secrets from conf"
    end

    local body, err = core.request.get_body_table()
    if not body then
        return 400, err
    end

    local msgs = body.messages
    if not msgs or type(msgs) ~= "table" or #msgs < 1 then
        return 400, "messages not found in request body"
    end

    local provider = conf.provider[next(conf.provider)]

    -- TODO support secret
    local credentials = aws_instance:Credentials({
        accessKeyId = provider.access_key_id,
        secretAccessKey = provider.secret_access_key,
        sessionToken = provider.session_token,
    })

    local default_endpoint = "https://comprehend." .. provider.region .. ".amazonaws.com"
    local scheme, host, port = unpack(http:parse_uri(provider.endpoint or default_endpoint))
    local endpoint = scheme .. "://" .. host
    aws_instance.config.endpoint = endpoint
    aws_instance.config.ssl_verify = false

    local comprehend = aws_instance:Comprehend({
        credentials = credentials,
        endpoint = endpoint,
        region = provider.region,
        port = port,
    })

    local ai_module = require("apisix.plugins.ai." .. conf.type)
    local create_request_text_segments = ai_module.create_request_text_segments

    local text_segments = create_request_text_segments(msgs)
    local res, err = comprehend:detectToxicContent({
        LanguageCode = "en",
        TextSegments = text_segments,
    })

    if not res then
        core.log.error("failed to send request to ", provider, ": ", err)
        return 500, err
    end

    local results = res.body and res.body.ResultList
    if not results or type(results) ~= "table" or #results < 1 then
        return 500, "failed to get moderation results from response"
    end

    for _, result in ipairs(results) do
        if conf.moderation_categories then
            for _, item in pairs(result.Labels) do
                if not conf.moderation_categories[item.Name] then
                    goto continue
                end
                if item.Score > conf.moderation_categories[item.Name] then
                    return 400, "request body exceeds " .. item.Name .. " threshold"
                end
                ::continue::
            end
        end

        if result.Toxicity > conf.toxicity_level then
            return 400, "request body exceeds toxicity threshold"
        end
    end
end

return _M
