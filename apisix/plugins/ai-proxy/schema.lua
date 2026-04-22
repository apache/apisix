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
local schema_def = require("apisix.schema_def")
local ai_providers_schema = require("apisix.plugins.ai-providers.schema")
local protocols = require("apisix.plugins.ai-protocols")
local ipairs = ipairs

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
        gcp = {
            type = "object",
            description = 'Whether to use GCP service account for authentication,'
            .. ' support set env GCP_SERVICE_ACCOUNT.',
            properties = {
                service_account_json = {
                    type = "string",
                    description = "GCP service account JSON content for authentication",
                },
                max_ttl = {
                    type = "integer",
                    minimum = 1,
                    description = "Maximum TTL (in seconds) for GCP access token caching",
                },
                expire_early_secs = {
                    type = "integer",
                    minimum = 0,
                    description = "Expire the access token early by specified seconds to avoid " ..
                                                                "edge cases",
                    default = 60,
                },
            }
        },
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

-- Build per-target-protocol request body override schema.
-- Each registered protocol gets an optional "any-shape object" entry.
local request_body_override_properties = {}
for _, proto_name in ipairs(protocols.names()) do
    request_body_override_properties[proto_name] = {
        type = "object",
        description = "Deep-merged into the outgoing request body when the "
            .. "target protocol is '" .. proto_name .. "'.",
        additionalProperties = true,
    }
end

local request_body_override_schema = {
    type = "object",
    description = "Per target-protocol request body overrides. Keys are target "
        .. "protocol names; values are partial request bodies that are "
        .. "deep-merged into the outgoing body (objects merged recursively, "
        .. "arrays and scalars replaced wholesale).",
    properties = request_body_override_properties,
    additionalProperties = false,
}

local llm_options_schema = {
    type = "object",
    properties = {
        max_tokens = {
            type = "integer",
            minimum = 1,
            description = "Maximum number of output tokens. APISIX automatically "
                .. "maps this to the correct field name for the target provider "
                .. "(e.g. max_completion_tokens for OpenAI, max_output_tokens "
                .. "for Responses API). Always force-overwrites the client value.",
        },
    },
    additionalProperties = false,
}

local override_schema = {
    type = "object",
    properties = {
        endpoint = {
            type = "string",
            description = "To be specified to override the endpoint of the AI Instance",
        },
        llm_options = llm_options_schema,
        request_body = request_body_override_schema,
        request_body_force_override = {
            type = "boolean",
            default = false,
            description = "When false (default), client request body fields take "
                .. "priority and request_body override values only fill in "
                .. "missing fields. When true, request_body override values "
                .. "forcefully overwrite client fields.",
        },
    },
}

local provider_vertex_ai_schema = {
    type = "object",
    properties = {
        project_id = {
            type = "string",
            description = "Google Cloud Project ID",
        },
        region = {
            type = "string",
            description = "Google Cloud Region",
        },
    },
    required = { "project_id", "region" },
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
                enum = ai_providers_schema.providers,
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
            override = override_schema,
            checks = {
                type = "object",
                properties = {
                    active = schema_def.health_checker_active,
                },
                required = {"active"}
            }
        },
        required = {"name", "provider", "auth", "weight"},
        ["if"] = {
            properties = { provider = { enum = { "vertex-ai" } } },
        },
        ["then"] = {
            properties = {
                provider_conf = provider_vertex_ai_schema,
            },
            oneOf = {
                { required = { "provider_conf" } },
                { required = { "override" } },
            },
        },
        ["else"] = {},
    },
}

local logging_schema = {
    type = "object",
    properties = {
        summaries = {
            type = "boolean",
            default = false,
            description = "Record user request llm model, duration, req/res token"
        },
        payloads = {
            type = "boolean",
            default = false,
            description = "Record user request and response payload"
        }
    }
}

_M.ai_proxy_schema = {
    type = "object",
    properties = {
        provider = {
            type = "string",
            description = "Type of the AI service instance.",
            enum = ai_providers_schema.providers,
        },
        logging = logging_schema,
        auth = auth_schema,
        options = model_options_schema,
        timeout = {
            type = "integer",
            minimum = 1,
            maximum = 600000,
            default = 30000,
            description = "timeout in milliseconds",
        },
        max_stream_duration_ms = {
            type = "integer",
            minimum = 1,
            description = "Maximum wall-clock duration (in milliseconds) for a "
                       .. "streaming AI response. If the upstream keeps sending "
                       .. "data past this deadline, the connection is closed. "
                       .. "Unset means no cap. Use this to protect the gateway "
                       .. "from upstream bugs that produce tokens indefinitely.",
        },
        max_response_bytes = {
            type = "integer",
            minimum = 1,
            description = "Maximum total bytes read from the upstream for a "
                       .. "single AI response (streaming or non-streaming). If "
                       .. "exceeded, the connection is closed. Unset means no cap.",
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
        override = override_schema,
    },
    required = {"provider", "auth"},
    encrypt_fields = {"auth.header", "auth.query", "auth.gcp.service_account_json"},
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
        logging = logging_schema,
        fallback_strategy = {
            anyOf = {
              {
                type = "string",
                enum = {"instance_health_and_rate_limiting", "http_429", "http_5xx"}
              },
              {
                type = "array",
                items = {
                  type = "string",
                  enum = {"rate_limiting", "http_429", "http_5xx"}
                }
              }
            }
        },
        timeout = {
            type = "integer",
            minimum = 1,
            maximum = 600000,
            default = 30000,
            description = "timeout in milliseconds",
        },
        max_stream_duration_ms = {
            type = "integer",
            minimum = 1,
            description = "Maximum wall-clock duration (in milliseconds) for a "
                       .. "streaming AI response. If the upstream keeps sending "
                       .. "data past this deadline, the connection is closed. "
                       .. "Unset means no cap. Use this to protect the gateway "
                       .. "from upstream bugs that produce tokens indefinitely.",
        },
        max_response_bytes = {
            type = "integer",
            minimum = 1,
            description = "Maximum total bytes read from the upstream for a "
                       .. "single AI response (streaming or non-streaming). If "
                       .. "exceeded, the connection is closed. Unset means no cap.",
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
    required = {"instances"},
    encrypt_fields = {
        "instances.auth.header",
        "instances.auth.query",
        "instances.auth.gcp.service_account_json",
    },
}

return  _M
