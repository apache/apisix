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
        query = auth_item_schema,
    },
    additionalProperties = false,
}

local model_options_schema = {
    description = "Key/value settings for the model",
    type = "object",
    properties = {
        model = {
            type = "string",
            description = "Model to execute.",
        },
    },
    additionalProperties = true,
}

local ai_instance_schema = {
    type = "array",
    minItems = 1,
    items = {
        type = "object",
        properties = {
            name = {
                type = "string",
                minLength = 1,
                maxLength = 100,
                description = "Name of the AI service instance.",
            },
            provider = {
                type = "string",
                description = "Type of the AI service instance.",
                enum = { "openai", "deepseek", "aimlapi", "openai-compatible" }, -- add more providers later

            },
            priority = {
                type = "integer",
                description = "Priority of the provider for load balancing",
                default = 0,
            },
            weight = {
                type = "integer",
                minimum = 0,
            },
            auth = auth_schema,
            options = model_options_schema,
            override = {
                type = "object",
                properties = {
                    endpoint = {
                        type = "string",
                        description = "To be specified to override the endpoint of the AI Instance",
                    },
                },
            },
        },
        required = {"name", "provider", "auth", "weight"}
    },
}


_M.ai_proxy_schema = {
    type = "object",
    properties = {
        provider = {
            type = "string",
            description = "Type of the AI service instance.",
            enum = { "openai", "deepseek", "aimlapi", "openai-compatible" }, -- add more providers later

        },
        auth = auth_schema,
        options = model_options_schema,
        timeout = {
            type = "integer",
            minimum = 1,
            default = 30000,
            description = "timeout in milliseconds",
        },
        keepalive = {type = "boolean", default = true},
        keepalive_timeout = {
            type = "integer",
            minimum = 1000,
            default = 60000,
            description = "keepalive timeout in milliseconds",
        },
        keepalive_pool = {type = "integer", minimum = 1, default = 30},
        ssl_verify = {type = "boolean", default = true },
        override = {
            type = "object",
            properties = {
                endpoint = {
                    type = "string",
                    description = "To be specified to override the endpoint of the AI Instance",
                },
            },
        },
    },
    required = {"provider", "auth"}
}

_M.ai_proxy_multi_schema = {
    type = "object",
    properties = {
        balancer = {
            type = "object",
            properties = {
                algorithm = {
                    type = "string",
                    enum = { "chash", "roundrobin" },
                },
                hash_on = {
                    type = "string",
                    default = "vars",
                    enum = {
                      "vars",
                      "header",
                      "cookie",
                      "consumer",
                      "vars_combinations",
                    },
                },
                key = {
                    description = "the key of chash for dynamic load balancing",
                    type = "string",
                },
            },
            default = { algorithm = "roundrobin" }
        },
        instances = ai_instance_schema,
        fallback_strategy = {
            type = "string",
            enum = { "instance_health_and_rate_limiting" },
            default = "instance_health_and_rate_limiting",
        },
        timeout = {
            type = "integer",
            minimum = 1,
            default = 30000,
            description = "timeout in milliseconds",
        },
        keepalive = {type = "boolean", default = true},
        keepalive_timeout = {
            type = "integer",
            minimum = 1000,
            default = 60000,
            description = "keepalive timeout in milliseconds",
        },
        keepalive_pool = {type = "integer", minimum = 1, default = 30},
        ssl_verify = {type = "boolean", default = true },
    },
    required = {"instances"}
}

_M.chat_request_schema = {
    type = "object",
    properties = {
        messages = {
            type = "array",
            minItems = 1,
            items = {
                properties = {
                    role = {
                        type = "string",
                        enum = {"system", "user", "assistant"}
                    },
                    content = {
                        type = "string",
                        minLength = "1",
                    },
                },
                additionalProperties = false,
                required = {"role", "content"},
            },
        }
    },
    required = {"messages"}
}

return  _M
