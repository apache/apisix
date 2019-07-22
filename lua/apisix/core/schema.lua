local json = require('rapidjson')
local schema_validator = json.SchemaValidator
local schema_doc = json.SchemaDocument
local json_doc = json.Document


local cached_sd = require("apisix.core.lrucache").new({count = 1000, ttl = 0})


local _M = {version = 0.2}


local function create_validator(schema)
    local sd = schema_doc(schema)
    local validator = schema_validator(sd)

    -- need to cache `validator` and `sd` object at same time
    return {validator, sd}
end


-- You can follow this document to write schema:
-- https://github.com/Tencent/rapidjson/blob/master/bin/draft-04/schema
-- rapidjson not supported `format` in draft-04 yet
function _M.check(schema, json)
    local validator = cached_sd(schema, nil, create_validator, schema)[1]

    local d = json_doc(json)
    return validator:validate(d)
end


local plugins_schema = {
    type = "object"
}


local id_schema = {
    anyOf = {
        {
            type = "string", minLength = 1, maxLength = 32,
            pattern = [[^[0-9]+$]]
        },
        {type = "integer", minimum = 1}
    }
}


-- todo: support all option
--   default value: https://github.com/Kong/lua-resty-healthcheck/
--   blob/master/lib/resty/healthcheck.lua#L1121
local health_checker = {
    type = "object",
    properties = {
        active = {
            type = "object",
            properties = {
                http_path = {type = "string"},
                host = {type = "string"},
                healthy = {
                    type = "object",
                    properties = {
                        interval = {type = "integer", minimum = 1},
                        successes = {type = "integer", minimum = 1}
                    }
                },
                unhealthy = {
                    type = "object",
                    properties = {
                        interval = {type = "integer", minimum = 1},
                        http_failures = {type = "integer", minimum = 1}
                    }
                }
            }
        },
        passive = {
            type = "object",
            properties = {
                type = {
                    type = "string",
                    enum = {"http", "https", "tcp"},
                },
                healthy = {
                    type = "object",
                    properties = {
                        http_statuses = {
                            type = "array",
                            items = {
                                type = "integer",
                                minimum = 200,
                                maximum = 599,
                            },
                            uniqueItems = true,
                        },
                        successes = {type = "integer", minimum = 1}
                    }
                },
                unhealthy = {
                    type = "object",
                    properties = {
                        http_statuses = {
                            type = "array",
                            items = {
                                type = "integer",
                                minimum = 200,
                                maximum = 599,
                            },
                            uniqueItems = true,
                        },
                        tcp_failures = {type = "integer"},
                        timeouts = {type = "integer"},
                        http_failures = {type = "integer"},
                    }
                }
            }
        }
    }
}


local upstream_schema = {
    type = "object",
    properties = {
        nodes = {
            description = "nodes of upstream",
            type = "object",
            patternProperties = {
                [".*"] = {
                    description = "weight of node",
                    type = "integer",
                    minimum = 1,
                }
            },
            minProperties = 1,
        },
        type = {
            description = "algorithms of load balancing",
            type = "string",
            enum = {"chash", "roundrobin"}
        },
        checks = health_checker,
        key = {
            description = "the key of chash for dynamic load balancing",
            type = "string",
            enum = {"remote_addr"},
        },
        desc = {type = "string", maxLength = 256},
        id = id_schema
    },
    required = {"nodes", "type"},
    additionalProperties = false,
}


_M.route = [[{
    "type": "object",
    "properties": {
        "methods": {
            "type": "array",
            "items": {
                "description": "HTTP method",
                "type": "string",
                "enum": ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD",
                         "OPTIONS"]
            },
            "uniqueItems": true
        },
        "desc": {"type": "string", "maxLength": 256},
        "plugins": ]] .. json.encode(plugins_schema) .. [[,
        "upstream": ]] .. json.encode(upstream_schema) .. [[,
        "uri": {
            "type": "string"
        },
        "host": {
            "type": "string",
            "pattern": "^\\*?[0-9a-zA-Z-.]+$"
        },
        "remote_addr": {
            "description": "client IP",
            "type": "string",
            "anyOf": [
              {"pattern": "^[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}$"},
              {"pattern": "^[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}]]
              .. [[/[0-9]{1,2}$"}
            ]
        },
        "service_id": ]] .. json.encode(id_schema) .. [[,
        "upstream_id": ]] .. json.encode(id_schema) .. [[,
        "id": ]] .. json.encode(id_schema) .. [[
    },
    "anyOf": [
        {"required": ["plugins", "uri"]},
        {"required": ["upstream", "uri"]},
        {"required": ["upstream_id", "uri"]},
        {"required": ["service_id", "uri"]}
    ],
    "additionalProperties": false
}]]


_M.service = {
    type = "object",
    properties = {
        id = id_schema,
        plugins = plugins_schema,
        upstream = upstream_schema,
        upstream_id = id_schema,
        desc = {type = "string", maxLength = 256},
    },
    anyOf = {
        {required = {"upstream"}},
        {required = {"upstream_id"}},
        {required = {"plugins"}},
    },
    additionalProperties = false,
}


_M.consumer = {
    type = "object",
    properties = {
        username = {
            type = "string", minLength = 1, maxLength = 32,
            pattern = [[^[a-zA-Z0-9_]+$]]
        },
        plugins = plugins_schema,
        desc = {type = "string", maxLength = 256},
    },
    required = {"username"},
    additionalProperties = false,
}


_M.upstream = upstream_schema


_M.ssl = {
    type = "object",
    properties = {
        cert = {
            type = "string", minLength = 128, maxLength = 4096
        },
        key = {
            type = "string", minLength = 128, maxLength = 4096
        },
        sni = {
            type = "string",
            pattern = [[^\*?[0-9a-zA-Z-.]+$]],
        }
    },
    required = {"sni", "key", "cert"},
    additionalProperties = false,
}


return _M
