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
local _M = {}

local auth_item_schema = {
    type = "object",
    patternProperties = {
        ["^[a-zA-Z0-9._-]+$"] = {
            type = "string"
        }
    }
}

local auth_schema = {
    type = "object",
    patternProperties = {
        header = auth_item_schema,
        query = auth_item_schema
    },
    additionalProperties = false
}

local model_options_schema = {
    description = "Key/value settings for the model",
    type = "object",
    properties = {
        max_tokens = {
            type = "integer",
            description = "Defines the max_tokens, if using chat or completion models.",
            default = 256

        },
        input_cost = {
            type = "number",
            description = "Defines the cost per 1M tokens in your prompt.",
            minimum = 0

        },
        output_cost = {
            type = "number",
            description = "Defines the cost per 1M tokens in the output of the AI.",
            minimum = 0

        },
        temperature = {
            type = "number",
            description = "Defines the matching temperature, if using chat or completion models.",
            minimum = 0.0,
            maximum = 5.0

        },
        top_p = {
            type = "number",
            description = "Defines the top-p probability mass, if supported.",
            minimum = 0,
            maximum = 1

        },
        stream = {
            description = "Stream response by SSE",
            type = "boolean"
        }
    }
}

_M.ai_proxy_rewrite_schema = {
    type = "object",
    properties = {
        prompt = {
            type = "string",
            description = "The prompt to rewrite"
        },
        provider = {
            type = "string",
            description = "Name of the AI service provider.",
            enum = {"openai", "openai-compatible", "deepseek"} -- add more providers later
        },
        auth = auth_schema,
        options = model_options_schema,
        override = {
            type = "object",
            properties = {
                endpoint = {
                    type = "string",
                    description = "To be specified to override the host of the AI provider"
                }
            }
        },
        timeout = {
            type = "integer",
            minimum = 1,
            maximum = 60000,
            default = 3000,
            description = "timeout in milliseconds"
        },
        keepalive = {
            type = "boolean",
            default = true
        },
        keepalive_timeout = {
            type = "integer",
            minimum = 1000,
            default = 60000
        },
        keepalive_pool = {
            type = "integer",
            minimum = 1,
            default = 30
        },
        ssl_verify = {
            type = "boolean",
            default = true
        }
    },
    required = {"prompt", "provider", "auth"}
}

