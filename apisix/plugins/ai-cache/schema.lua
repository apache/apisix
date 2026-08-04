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

local core         = require("apisix.core")
local redis_schema = require("apisix.utils.redis-schema")
local binding      = require("apisix.plugins.ai-protocols.binding")

local policy_to_additional_properties = core.table.deepcopy(redis_schema.schema)

local _M = {
    type = "object",
    properties = {
        exact = {
            type = "object",
            properties = {
                ttl = { type = "integer", minimum = 1, default = 3600 },
            },
            default = {},
        },

        cache_key = {
            type = "object",
            properties = {
                share_across_routes = { type = "boolean", default = false },
                include_consumer = { type = "boolean", default = false },
                include_vars = {
                    type = "array",
                    items = { type = "string" },
                    default = {},
                },
            },
            default = {},
        },

        max_cache_body_size = {
            type = "integer", minimum = 0, default = 1048576,
        },

        cache_headers = {
            type = "boolean", default = true,
        },

        fail_mode = binding.schema_property("skip"),

        bypass_on = {
            type = "array",
            minItems = 1,
            items = {
                type = "object",
                properties = {
                    header = { type = "string", minLength = 1 },
                    equals = { type = "string" },
                },
                required = { "header", "equals" },
            },
        },

        policy = {
            type = "string",
            enum = { "redis" },
            default = "redis",
        },

        layers = {
            type = "array",
            items = { enum = { "exact", "semantic" } },
            minItems = 1,
            uniqueItems = true,
            contains = { const = "exact" },
            default = { "exact" },
        },

        semantic = {
            type = "object",
            properties = {
                similarity_threshold = {
                    type = "number", minimum = 0, maximum = 1, default = 0.95,
                },
                top_k = { type = "integer", minimum = 1, default = 1 },
                distance_metric = { enum = { "cosine" }, default = "cosine" },
                ttl = { type = "integer", minimum = 1, default = 86400 },
                match = {
                    type = "object",
                    properties = {
                        message_countback = { type = "integer", minimum = 1, default = 1 },
                        ignore_system_prompts = { type = "boolean", default = true },
                        ignore_assistant_prompts = { type = "boolean", default = true },
                        ignore_tool_prompts = { type = "boolean", default = true },
                    },
                    default = {},
                },
                embedding = {
                    type = "object",
                    properties = {
                        openai = {
                            type = "object",
                            properties = {
                                endpoint = { type = "string" },
                                model = { type = "string" },
                                api_key = { type = "string" },
                                dimensions = { type = "integer", minimum = 1 },
                                ssl_verify = { type = "boolean", default = true },
                                timeout = { type = "integer", minimum = 1, default = 5000 },
                            },
                            required = { "model", "api_key" },
                        },
                        azure_openai = {
                            type = "object",
                            properties = {
                                endpoint = { type = "string" },
                                api_key = { type = "string" },
                                dimensions = { type = "integer", minimum = 1 },
                                ssl_verify = { type = "boolean", default = true },
                                timeout = { type = "integer", minimum = 1, default = 5000 },
                            },
                            required = { "endpoint", "api_key" },
                        },
                    },
                    oneOf = { { required = { "openai" } }, { required = { "azure_openai" } } },
                },
                vector_search = {
                    type = "object",
                    properties = {
                        redis = {
                            type = "object",
                            properties = { index = { type = "string", default = "ai-cache" } },
                            default = {},
                        },
                    },
                    required = { "redis" },
                },
            },
            required = { "embedding", "vector_search" },
        },
    },
    ["if"] = {
        properties = {
            policy = {
                enum = { "redis" },
            },
        },
    },
    ["then"] = policy_to_additional_properties.redis,
    allOf = {
        {
            ["if"] = { properties = { layers = { contains = { const = "semantic" } } },
                       required = { "layers" } },
            ["then"] = { required = { "semantic" } },
        },
    },
    encrypt_fields = {
        "redis_password",
        "semantic.embedding.openai.api_key",
        "semantic.embedding.azure_openai.api_key",
    },
}

return _M
