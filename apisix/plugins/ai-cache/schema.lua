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

local policy_to_additional_properties = core.table.deepcopy(redis_schema.schema)

local _M = {
    type = "object",
    properties = {
        layers = {
            type = "array",
            items = {
                enum = { "exact" },
            },
            minItems = 1,
            uniqueItems = true,
            default = { "exact" },
        },

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

        bypass_on = {
            type = "array",
            minItems = 1,
            items = {
                type = "object",
                properties = {
                    header = { type = "string" },
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
    },
    ["if"] = {
        properties = {
            policy = {
                enum = { "redis" },
            },
        },
    },
    ["then"] = policy_to_additional_properties.redis,
    encrypt_fields = { "redis_password" },
}

return _M
