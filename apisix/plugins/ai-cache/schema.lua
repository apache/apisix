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

local policy_to_additional_properties = redis_schema.schema

local schema = {
    type = "object",
    properties = {
        exact = {
            type = "object",
            properties = {
                ttl = {
                    type = "integer",
                    minimum = 1,
                    maximum = 2592000,
                    default = 3600,
                },
            },
            additionalProperties = false,
            default = { ttl = 3600 },
        },
        policy = {
            type = "string",
            enum = { "redis", "redis-cluster" },
            default = "redis",
        },
    },
    required = { "policy" },
    ["if"] = {
        properties = {
            policy = { enum = { "redis" } },
        },
    },
    ["then"] = policy_to_additional_properties.redis,
    ["else"] = {
        ["if"] = {
            properties = {
                policy = { enum = { "redis-cluster" } },
            },
        },
        ["then"] = policy_to_additional_properties["redis-cluster"],
    },
}

return {
    schema = schema,
    encrypt_fields = { "redis_password" },
}
