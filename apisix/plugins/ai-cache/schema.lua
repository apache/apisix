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
            description = "Embedding API provider.",
        },
        model = {
            type = "string",
            description = "Embedding model name. Sent in the request body for "
                       .. "provider: openai; ignored for provider: azure_openai "
                       .. "(Azure infers the model from the deployment URL).",
        },
        endpoint = {
            type = "string",
            description = "Embedding API endpoint URL.",
        },
        api_key = {
            type = "string",
            description = "API key for the embedding provider.",
        },
        timeout = {
            type = "integer",
            minimum = 1,
            maximum = 600000,
            default = 5000,
            description = "HTTP request timeout in milliseconds for embedding API calls.",
        },
        ssl_verify = {
            type = "boolean",
            default = true,
            description = "Whether to verify the embedding endpoint's TLS certificate.",
        },
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
            description = "Minimum cosine similarity required for a semantic-layer hit.",
        },
        top_k = {
            type = "integer",
            minimum = 1,
            maximum = 100,
            default = 1,
            description = "Number of nearest-neighbor candidates the index returns; "
                       .. "the first candidate above similarity_threshold is used.",
        },
        ttl = {
            type = "integer",
            minimum = 1,
            default = 86400,
            description = "Time-to-live in seconds for semantic-layer entries.",
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
            description = "Time-to-live in seconds for exact-layer entries.",
        },
    },
}


local bypass_item_schema = {
    type = "object",
    properties = {
        header = {
            type = "string",
            description = "Request header name to inspect.",
        },
        equals = {
            type = "string",
            description = "Value to match against the header. "
                       .. "If equal, the request bypasses the cache.",
        },
    },
    required = { "header", "equals" },
}

local headers_schema = {
    type = "object",
    properties = {
        cache_status = {
            type = "string",
            default = "X-AI-Cache-Status",
            description = "Response header name for cache status "
                       .. "(HIT-L1 / HIT-L2 / MISS / BYPASS).",
        },
        cache_similarity = {
            type = "string",
            default = "X-AI-Cache-Similarity",
            description = "Response header name for the similarity score of a semantic-layer hit.",
        },
        cache_age = {
            type = "string",
            default = "X-AI-Cache-Age",
            description = "Response header name for the age in seconds of an exact-layer hit.",
        },
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
            description = "Cache layers to enable, queried in order.",
        },
        cache_key = {
            type = "object",
            properties = {
                include_consumer = {
                    type = "boolean",
                    default = false,
                    description = "If true, partition the cache by consumer name.",
                },
                include_vars = {
                    type = "array",
                    items = { type = "string" },
                    default = {},
                    description = "Additional ctx.var names included in the cache key, "
                               .. "for example [\"$http_x_tenant_id\"].",
                },
            },
        },
        exact = exact_schema,
        semantic = semantic_schema,
        bypass_on = {
            type = "array",
            items = bypass_item_schema,
            description = "List of {header, equals} rules. "
                       .. "If any matches, the request bypasses the cache.",
        },
        headers = headers_schema,
        max_cache_body_size = {
            type = "integer",
            minimum = 1,
            default = 1048576,
            description = "Maximum response size in bytes to write to cache. "
                       .. "Larger responses pass through but are not cached.",
        },
    },
    allOf = { redis_schema.schema.redis },
    encrypt_fields = { "semantic.embedding.api_key", "redis_password" },
}

return _M
