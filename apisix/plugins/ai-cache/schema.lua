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

local redis_schema = require("apisix.utils.redis-schema")

local _M = {}

local embedding_schema = {
    type = "object",
    properties = {
        provider = {
            type = "string",
            enum = { "openai", "azure_openai" },
        },
        model = { type = "string" },
        endpoint = { type = "string" },
        api_key = { type = "string" },
        timeout = {
            type = "integer",
            minimum = 1,
            maximum = 600000,
            default = 5000,
            description = "timeout in milliseconds",
        },
        ssl_verify = { type = "boolean", default = true },
    },
    required = { "provider", "endpoint", "api_key" },
}

local semantic_schema = {
    type = "object",
    properties = {
        similarity_threshold = {
            type = "number",
            minimum = 0,
            maximum = 1,
            default = 0.95,
        },
        top_k = {
            type = "integer",
            minimum = 1,
            default = 1,
        },
        ttl = {
            type = "integer",
            minimum = 1,
            default = 86400,
        },
        embedding = embedding_schema,
    },
    required = { "embedding" },
}

local exact_schema = {
    type = "object",
    properties = {
        ttl = {
            type = "integer",
            minimum = 1,
            default = 3600,
        },
    },
}


local bypass_item_schema = {
    type = "object",
    properties = {
        header = { type = "string" },
        equals = { type = "string" },
    },
    required = { "header", "equals" },
}

local headers_schema = {
    type = "object",
    properties = {
        cache_status = { type = "string", default = "X-AI-Cache-Status" },
        cache_similarity = { type = "string", default = "X-AI-Cache-Similarity" },
        cache_age = { type = "string", default = "X-AI-Cache-Age" },
    },
}

_M.schema = {
    type = "object",
    properties = {
        layers = {
            type = "array",
            items = { type = "string", enum = { "exact", "semantic" } },
            uniqueItems = true,
            minItems = 1,
            default = { "exact", "semantic" },
        },
        cache_key = {
            type = "object",
            properties = {
                include_consumer = {type = "boolean", default = false },
                include_vars = {
                    type = "array",
                    items = { type = "string" },
                    default = {},
                },
            },
        },
        exact = exact_schema,
        semantic = semantic_schema,
        bypass_on = {
            type = "array",
            items = bypass_item_schema,
        },
        headers = headers_schema,
        max_cache_body_size = {
            type = "integer",
            minimum = 1,
            default = 1048576,
        },
    },
    allOf = { redis_schema.schema.redis },
    encrypt_fields = { "semantic.embedding.api_key", "redis_password" },
}

return _M
