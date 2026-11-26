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
local next    = next
local require = require
local ngx_req = ngx.req

local http      = require("resty.http")
local core      = require("apisix.core")
local protocols = require("apisix.plugins.ai-protocols")

local azure_openai_embeddings = require("apisix.plugins.ai-rag.embeddings.azure_openai").schema
local azure_ai_search_schema = require("apisix.plugins.ai-rag.vector-search.azure_ai_search").schema
local qdrant_schema = require("apisix.plugins.ai-rag.vector-search.qdrant").schema

local HTTP_INTERNAL_SERVER_ERROR = ngx.HTTP_INTERNAL_SERVER_ERROR
local HTTP_BAD_REQUEST = ngx.HTTP_BAD_REQUEST

local schema = {
    type = "object",
    properties = {
        ssl_verify = {
            type = "boolean",
            default = true,
        },
        embeddings_provider = {
            type = "object",
            properties = {
                azure_openai = azure_openai_embeddings
            },
            -- ensure only one provider can be configured while implementing support for
            -- other providers
            required = { "azure_openai" },
            maxProperties = 1,
        },
        vector_search_provider = {
            type = "object",
            properties = {
                azure_ai_search = azure_ai_search_schema,
                qdrant = qdrant_schema,
            },
            minProperties = 1,
            maxProperties = 1,
            additionalProperties = false,
        },
    },
    required = { "embeddings_provider", "vector_search_provider" },
    encrypt_fields = {
        "embeddings_provider.azure_openai.api_key",
        "vector_search_provider.azure_ai_search.api_key",
        "vector_search_provider.qdrant.api_key",
    },
}

-- core.schema.check caches validators per table, so each provider pair needs its own
local request_schemas = {}

local function get_request_schema(key, embeddings_driver, vector_search_driver)
    if not request_schemas[key] then
        request_schemas[key] = {
            type = "object",
            properties = {
                ai_rag = {
                    type = "object",
                    properties = {
                        vector_search = vector_search_driver.request_schema,
                        embeddings = embeddings_driver.request_schema,
                    },
                    required = { "vector_search", "embeddings" }
                }
            }
        }
    end
    return request_schemas[key]
end

local _M = {
    version = 0.1,
    priority = 1060,
    name = "ai-rag",
    schema = schema,
}


function _M.check_schema(conf)
    core.utils.check_tls_bool({"ssl_verify"}, conf, _M.name)
    core.utils.check_https({
        "embeddings_provider.azure_openai.endpoint",
        "vector_search_provider.azure_ai_search.endpoint",
        "vector_search_provider.qdrant.endpoint",
    }, conf, _M.name)
    return core.schema.check(schema, conf)
end


function _M.access(conf, ctx)
    local httpc = http.new()
    local ssl_verify = conf.ssl_verify ~= false
    local body_tab, err = core.request.get_json_request_body_table()
    if not body_tab then
        return HTTP_BAD_REQUEST, err
    end
    if not body_tab["ai_rag"] then
        core.log.error("request body must have \"ai-rag\" field")
        return HTTP_BAD_REQUEST
    end

    local embeddings_provider = next(conf.embeddings_provider)
    local embeddings_provider_conf = conf.embeddings_provider[embeddings_provider]
    local embeddings_driver = require("apisix.plugins.ai-rag.embeddings." .. embeddings_provider)

    local vector_search_provider = next(conf.vector_search_provider)
    local vector_search_provider_conf = conf.vector_search_provider[vector_search_provider]
    local vector_search_driver = require("apisix.plugins.ai-rag.vector-search." ..
                                        vector_search_provider)

    local request_schema = get_request_schema(embeddings_provider .. "#" .. vector_search_provider,
                                              embeddings_driver, vector_search_driver)
    local ok, err = core.schema.check(request_schema, body_tab)
    if not ok then
        core.log.error("request body fails schema check: ", err)
        return HTTP_BAD_REQUEST
    end

    local embeddings, status, err = embeddings_driver.get_embeddings(embeddings_provider_conf,
                                                        body_tab["ai_rag"].embeddings, httpc,
                                                        ssl_verify)
    if not embeddings then
        core.log.error("could not get embeddings: ", err)
        return status, err
    end

    local search_body = body_tab["ai_rag"].vector_search
    search_body.embeddings = embeddings
    local res, status, err = vector_search_driver.search(vector_search_provider_conf,
                                                        search_body, httpc, ssl_verify)
    if not res then
        core.log.error("could not get vector_search result: ", err)
        return status, err
    end

    -- remove ai_rag from request body because their purpose is served
    -- also, these values will cause failure when proxying requests to LLM.
    body_tab["ai_rag"] = nil

    if res ~= "" then
        protocols.append_messages(body_tab, ctx, {{role = "user", content = res}})
    end

    local req_body_json, err = core.json.encode(body_tab)
    if not req_body_json then
        return HTTP_INTERNAL_SERVER_ERROR, err
    end

    ngx_req.set_body_data(req_body_json)
end


return _M
