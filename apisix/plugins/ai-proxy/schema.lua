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
local ai_drivers_schema = require("apisix.plugins.ai-drivers.schema")

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
                enum = ai_drivers_schema.providers,
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
            enum = ai_drivers_schema.providers,
        },
        logging = logging_schema,
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
