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

local auth_schema = {
    type = "object",
    properties = {
        type = {
            type = "string",
            enum = {"header", "param"}
        },
        name = {
            type = "string",
            description = "Name of the param/header carrying Authorization or API key.",
            minLength = 1,
        },
        value = {
            type = "string",
            description = "Full auth-header/param value.",
            minLength = 1,
             -- TODO encrypted = true,
        },
    },
    required = { "type", "name", "value" },
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
        upstream_host = {
            type = "string",
            description = "To be specified to override the host of the AI provider",
        },
        upstream_port = {
            type = "integer",
            description = "To be specified to override the AI provider port",

        },
        upstream_path = {
            type = "string",
            description = "To be specified to override the URL to the AI provider endpoints",
        },
        stream = {
            description = "Stream response by SSE",
            type = "boolean",
            default = false,
        }
    }
}

local model_schema = {
    type = "object",
    properties = {
        provider = {
            type = "string",
            description = "Name of the AI service provider.",
            oneOf = { "openai" }, -- add more providers later

        },
        name = {
            type = "string",
            description = "Model name to execute.",
        },
        options = model_options_schema,
        override = {
            type = "object",
            properties = {
                host = {
                    type = "string",
                    description = "To be specified to override the host of the AI provider",
                },
                port = {
                    type = "integer",
                    description = "To be specified to override the AI provider port",
                },
                path = {
                    type = "string",
                    description = "To be specified to override the URL to the AI provider endpoints",
                },
            }
        }
    },
    required = {"provider", "name"}
}

_M.plugin_schema = {
    type = "object",
    properties = {
        route_type = {
            type = "string",
            enum = { "llm/chat", "passthrough" }
        },
        auth = auth_schema,
        model = model_schema,
    },
    required = {"route_type", "model", "auth"}
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
