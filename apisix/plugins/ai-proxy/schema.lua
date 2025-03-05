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
            maximum = 5.0,

        },
        top_p = {
            type = "number",
            description = "Defines the top-p probability mass, if supported.",
            minimum = 0,
            maximum = 1,

        },
        stream = {
            description = "Stream response by SSE",
            type = "boolean",
        }
    }
}

local model_schema = {
    type = "object",
    properties = {
        provider = {
            type = "string",
            description = "Name of the AI service provider.",
            enum = { "openai", "openai-compatible", "deepseek" }, -- add more providers later
        },
        name = {
            type = "string",
            description = "Model name to execute.",
        },
        options = model_options_schema,
        override = {
            type = "object",
            properties = {
                endpoint = {
                    type = "string",
                    description = "To be specified to override the host of the AI provider",
                },
            }
        }
    },
    required = {"provider", "name"}
}

local provider_schema = {
    type = "array",
    minItems = 1,
    items = {
        type = "object",
        properties = {
            name = {
                type = "string",
                description = "Name of the AI service provider.",
                enum = { "openai", "deepseek", "openai-compatible" }, -- add more providers later

            },
            model = {
                type = "string",
                description = "Model to execute.",
            },
            priority = {
                type = "integer",
                description = "Priority of the provider for load balancing",
                default = 0,
            },
            weight = {
                type = "integer",
            },
            auth = auth_schema,
            options = model_options_schema,
            override = {
                type = "object",
                properties = {
                    endpoint = {
                        type = "string",
                        description = "To be specified to override the host of the AI provider",
                    },
                },
            },
        },
        required = {"name", "model", "auth"}
    },
}


_M.ai_proxy_schema = {
    type = "object",
    properties = {
        auth = auth_schema,
        model = model_schema,
        timeout = {
            type = "integer",
            minimum = 1,
            maximum = 60000,
            default = 3000,
            description = "timeout in milliseconds",
        },
        keepalive = {type = "boolean", default = true},
        keepalive_pool = {type = "integer", minimum = 1, default = 30},
        ssl_verify = {type = "boolean", default = true },
    },
    required = {"model", "auth"}
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
        providers = provider_schema,
        timeout = {
            type = "integer",
            minimum = 1,
            maximum = 60000,
            default = 3000,
            description = "timeout in milliseconds",
        },
        keepalive = {type = "boolean", default = true},
        keepalive_timeout = {type = "integer", minimum = 1000, default = 60000},
        keepalive_pool = {type = "integer", minimum = 1, default = 30},
        ssl_verify = {type = "boolean", default = true },
    },
    required = {"providers", }
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
