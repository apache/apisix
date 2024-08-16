local _M = {}

local auth_schema = {
    type = "object",
    properties = {
        header_name = {
            type = "string",
            description =
            "Name of the header carrying Authorization or API key.",
        },
        header_value = {
            type = "string",
            description =
            "Full auth-header value.",
            encrypted = true, -- TODO
        },
        param_name = {
            type = "string",
            description = "Name of the param carrying Authorization or API key.",
        },
        param_value = {
            type = "string",
            description = "full parameter value for 'param_name'.",
            encrypted = true, -- TODO
        },
        param_location = {
            type = "string",
            description =
            "location of the auth param: query string, or the POST form/JSON body.",
            oneOf = { "query", "body" },
        },
        oneOf = {
            { required = { "header_name", "header_value" } },
            { required = { "param_name", "param_location", "param_value" } }
        }
    }
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
        response_streaming = {
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
            description = "AI provider request format - kapisix translates "
                .. "requests to and from the specified backend compatible formats.",
            oneOf = { "openai" }, -- add more providers later

        },
        name = {
            type = "string",
            description = "Model name to execute.",
        },
        options = model_options_schema,
    },
    required = {"provider"}
}

_M.plugin_schema = {
    type = "object",
    properties = {
        route_type = {
            type = "string",
            description = "The model's operation implementation, for this provider. " ..
                "Set to `preserve` to pass through without transformation.",
            enum = { "llm/chat", "llm/completions", "passthrough" }
        },
        auth = auth_schema,
        model = model_schema,
    },
    required = {"route_type", "model"}
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

_M.chat_completion_request_schema = {
    type = "object",
    properties = {
        prompt = {
            type = "string",
            minLength = 1
        }
    },
    required = {"prompt"}
}

return  _M
