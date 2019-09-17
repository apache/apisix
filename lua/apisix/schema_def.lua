local schema    = require('apisix.core.schema')
local json      = require("apisix.core.json")
local setmetatable = setmetatable


local _M = {version = 0.1}


setmetatable(_M, {__index = schema})


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


-- todo: support all options
--   default value: https://github.com/Kong/lua-resty-healthcheck/
--   blob/master/lib/resty/healthcheck.lua#L1121
local health_checker = {
    type = "object",
    properties = {
        active = {
            type = "object",
            properties = {
                type = {
                    type = "string",
                    enum = {"http", "https", "tcp"},
                    default = "http"
                },
                timeout = {type = "integer", default = 1},
                concurrency = {type = "integer", default = 10},
                host = {type = "string"},
                http_path = {type = "string", default = "/"},
                https_verify_certificate = {type = "boolean", default = true},
                healthy = {
                    type = "object",
                    properties = {
                        interval = {type = "integer", minimum = 1, default = 0},
                        http_statuses = {
                            type = "array",
                            minItems = 1,
                            items = {
                                type = "integer",
                                minimum = 200,
                                maximum = 599
                            },
                            uniqueItems = true,
                            default = {200, 302}
                        },
                        successes = {
                            type = "integer",
                            minimum = 1,
                            maximum = 254,
                            default = 2
                        }
                    }
                },
                unhealthy = {
                    type = "object",
                    properties = {
                        interval = {type = "integer", minimum = 1, default = 0},
                        http_statuses = {
                            type = "array",
                            minItems = 1,
                            items = {
                                type = "integer",
                                minimum = 200,
                                maximum = 599
                            },
                            uniqueItems = true,
                            default = {429, 404, 500, 501, 502, 503, 504, 505}
                        },
                        http_failures = {
                            type = "integer",
                            minimum = 1,
                            maximum = 254,
                            default = 5
                        },
                        tcp_failures = {
                            type = "integer",
                            minimum = 1,
                            maximum = 254,
                            default = 2
                        },
                        timeouts = {
                            type = "integer",
                            minimum = 1,
                            maximum = 254,
                            default = 3
                        }
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
                    default = "http"
                },
                healthy = {
                    type = "object",
                    properties = {
                        http_statuses = {
                            type = "array",
                            minItems = 1,
                            items = {
                                type = "integer",
                                minimum = 200,
                                maximum = 599,
                            },
                            uniqueItems = true,
                            default = {200, 201, 202, 203, 204, 205, 206, 207,
                                       208, 226, 300, 301, 302, 303, 304, 305,
                                       306, 307, 308}
                        },
                        successes = {
                            type = "integer",
                            minimum = 1,
                            maximum = 254,
                            default = 5
                        }
                    }
                },
                unhealthy = {
                    type = "object",
                    properties = {
                        http_statuses = {
                            type = "array",
                            minItems = 1,
                            items = {
                                type = "integer",
                                minimum = 200,
                                maximum = 599,
                            },
                            uniqueItems = true,
                            default = {429, 500, 503}
                        },
                        tcp_failures = {
                            type = "integer",
                            minimum = 1,
                            maximum = 254,
                            default = 2
                        },
                        timeouts = {
                            type = "integer",
                            minimum = 1,
                            maximum = 254,
                            default = 7
                        },
                        http_failures = {
                            type = "integer",
                            minimum = 1,
                            maximum = 254,
                            default = 5
                        },
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
        retries = {
            type = "integer",
            minimum = 1,
        },
        timeout = {
            type = "object",
            properties = {
                connect = {type = "number", minimum = 0},
                send = {type = "number", minimum = 0},
                read = {type = "number", minimum = 0},
            },
            required = {"connect", "send", "read"},
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
        id = id_schema,
        scheme = {
            description = "scheme of upstream",
            type = "string",
            enum = {"http", "https"},
        },
        host = {
            description = "host of upstream",
            type = "string",
        },
        upgrade = {
            description = "upgrade header for upstream",
            type = "string",
        },
        connection = {
            description = "connection header for upstream",
            type = "string",
        },
        uri = {
            description = "new uri for upstream",
            type = "string",
        },
        enable_websocket = {
            description = "enable websocket for request",
            type = "boolean",
        }
    },
    required = {"nodes", "type"},
    additionalProperties = false,
}


local route = [[{
    "type": "object",
    "properties": {
        "methods": {
            "type": "array",
            "items": {
                "description": "HTTP method",
                "type": "string",
                "enum": ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD",
                         "OPTIONS", "CONNECT", "TRACE"]
            },
            "uniqueItems": true
        },
        "service_protocol": {
            "enum": [ "grpc", "http" ]
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
        "vars": {
            "type": "array",
            "items": {
                "description": "Nginx builtin variable name and value",
                "type": "array"
            }
        },
        "remote_addr": {
            "description": "client IP",
            "type": "string",
            "anyOf": [
              {"pattern": "^[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}$"},
              {"pattern": "^[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}]]
              .. [[/[0-9]{1,2}$"},
              {"pattern": "^([a-f0-9]{0,4}:){0,8}(:[a-f0-9]{0,4}){0,8}$"}
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
do
    local route_t, err = json.decode(route)
    if err then
        error("invalid route: " .. route)
    end
    _M.route = route_t
end


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


_M.proto = {
    type = "object",
    properties = {
        content = {
            type = "string", minLength = 1, maxLength = 4096
        }
    },
    required = {"content"},
    additionalProperties = false,
}


_M.global_rule = {
    type = "object",
    properties = {
        plugins = plugins_schema
    },
    required = {"plugins"},
    additionalProperties = false,
}


local valid_ip_fmts = {
    {pattern = "^[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}$"},
    {pattern = "^[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}"
                .. "/[0-9]{1,2}$"},
    {pattern = "^([a-f0-9]{0,4}:){0,8}(:[a-f0-9]{0,4}){0,8}$"}
}


_M.stream_route = {
    type = "object",
    properties = {
        remote_addr = {
            description = "client IP",
            type = "string",
            anyOf = valid_ip_fmts,
        },
        server_addr = {
            description = "server IP",
            type = "string",
            anyOf = valid_ip_fmts,
        },
        server_port = {
            description = "server port",
            type = "number",
        },
        upstream = upstream_schema,
        upstream_id = id_schema,
        plugins = plugins_schema,
    }
}


return _M
