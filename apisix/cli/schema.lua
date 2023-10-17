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

local jsonschema = require("jsonschema")
local pairs = pairs
local pcall = pcall
local require = require


local _M = {}
local etcd_schema = {
    type = "object",
    properties = {
        health_check_timeout = {
            type = "integer"
        },
        startup_retry = {
            type = "integer"
        },
        resync_delay = {
            type = "integer",
        },
        user = {
            type = "string",
        },
        password = {
            type = "string",
        },
        tls = {
            type = "object",
            properties = {
                cert = {
                    type = "string",
                },
                key = {
                    type = "string",
                },
                verify = {
                    type = "boolean"
                }
            },
        },
        prefix = {
            type = "string",
        },
        host = {
            type = "array",
            items = {
                type = "string",
                pattern = [[^https?://]]
            },
            minItems = 1,
        },
        timeout = {
            type = "integer",
            default = 30,
            minimum = 1,
            description = "etcd connection timeout in seconds",
        },
    },
    required = { "prefix", "host" }
}

local admin_schema = {
    type = "object",
    properties = {
        admin_key = {
            type = "array",
            properties = {
                items = {
                    properties = {
                        name = { type = "string" },
                        key = { type = "string" },
                        role = { type = "string" },
                    }
                }
            }
        },
        admin_listen = {
            properties = {
                listen = { type = "string" },
                port = { type = "integer" },
            },
            default = {
                listen = "0.0.0.0",
                port = 9180,
            }
        },
        https_admin = {
            type = "boolean",
        },
        admin_key_required = {
            type = "boolean",
        },
        enable_admin_cors = {
            type = "boolean"
        },
        allow_admin = {
            type = "array",
            items = {
                type = "string"
            }
        },
        admin_api_mtls = {
            type = "object",
            properties = {
                admin_ssl_cert = {
                    type = "string"
                },
                admin_ssl_cert_key = {
                    type = "string"
                },
                admin_ssl_ca_cert = {
                    type = "string"
                }
            }
        },
        admin_api_version = {
            type = "string"
        }
    }
}

local config_schema = {
    type = "object",
    properties = {
        apisix = {
            properties = {
                node_listen = {
                    anyOf = {
                        {
                            type = "integer",
                            minimum = 1,
                            maximum = 65535
                        },
                        {
                            type = "array",
                            items = {
                                type = "integer",
                                minimum = 1,
                                maximum = 65535
                            }
                        },
                        {
                            type = "array",
                            items = {
                                type = "object",
                                properties = {
                                    port = {
                                        type = "integer",
                                        minimum = 1,
                                        maximum = 65535
                                    },
                                    ip = {
                                        type = "string",
                                    },
                                    enable_http2 = {
                                        type = "boolean",
                                    },
                                }
                            },
                        }
                    },
                },
                enable_admin = {
                    type = "boolean",
                },
                enable_dev_mode = {
                    type = "boolean",
                },
                enable_reuseport = {
                    type = "boolean",
                },
                show_upstream_status_in_response_header = {
                    type = "boolean",
                },
                enable_ipv6 = {
                    type = "boolean",
                },
                enable_server_tokens = {
                    type = "boolean",
                },
                extra_lua_path = {
                    type = "string"
                },
                extra_lua_cpath = {
                    type = "string"
                },
                lua_module_hook = {
                    pattern = "^[a-zA-Z._-]+$",
                },
                proxy_protocol = {
                    type = "object",
                    properties = {
                        listen_http_port = {
                            type = "integer",
                        },
                        listen_https_port = {
                            type = "integer",
                        },
                        enable_tcp_pp = {
                            type = "boolean",
                        },
                        enable_tcp_pp_to_upstream = {
                            type = "boolean",
                        },
                    }
                },
                proxy_cache = {
                    type = "object",
                    properties = {
                        zones = {
                            type = "array",
                            minItems = 1,
                            items = {
                                type = "object",
                                properties = {
                                    name = {
                                        type = "string",
                                    },
                                    memory_size = {
                                        type = "string",
                                    },
                                    disk_size = {
                                        type = "string",
                                    },
                                    disk_path = {
                                        type = "string",
                                    },
                                    cache_levels = {
                                        type = "string",
                                    },
                                },
                                oneOf = {
                                    {
                                        required = { "name", "memory_size" },
                                        maxProperties = 2,
                                    },
                                    {
                                        required = { "name", "memory_size", "disk_size",
                                            "disk_path", "cache_levels" },
                                    }
                                },
                            },
                            uniqueItems = true,
                        }
                    }
                },
                delete_uri_tail_slash = {
                    type = "boolean",
                },
                normalize_uri_like_servlet = {
                    type = "boolean",
                },
                router = {
                    type = "object",
                    properties = {
                        http = {
                            type = "string",
                            enum = { "radixtree_host_uri",
                                "radixtree_uri",
                                "radixtree_uri_with_parameter" },
                        },
                        ssl = {
                            type = "string",
                            enum = { "radixtree_host_uri",
                                "radixtree_uri",
                                "radixtree_uri_with_parameter",
                                "radixtree_sni" },
                        },
                    }
                },
                proxy_mode = {
                    type = "string",
                    enum = { "http", "stream", "http&stream" },
                },
                stream_proxy = {
                    type = "object",
                    properties = {
                        tcp = {
                            type = "array",
                            minItems = 1,
                            items = {
                                anyOf = {
                                    {
                                        type = "integer",
                                    },
                                    {
                                        type = "string",
                                    },
                                    {
                                        type = "object",
                                        properties = {
                                            addr = {
                                                anyOf = {
                                                    {
                                                        type = "integer",
                                                    },
                                                    {
                                                        type = "string",
                                                    },
                                                }
                                            },
                                            tls = {
                                                type = "boolean",
                                            }
                                        },
                                        required = { "addr" }
                                    },
                                },
                            },
                            uniqueItems = true,
                        },
                        udp = {
                            type = "array",
                            minItems = 1,
                            items = {
                                anyOf = {
                                    {
                                        type = "integer",
                                    },
                                    {
                                        type = "string",
                                    },
                                },
                            },
                            uniqueItems = true,
                        },
                    }
                },
                dns_resolver = {
                    type = "array",
                    minItems = 1,
                    items = {
                        type = "string",
                    }
                },
                dns_resolver_valid = {
                    type = "integer",
                },
                resolver_timeout = {
                    type = "integer",
                },
                enable_resolv_search_opt = {
                    type = "boolean",
                },
                ssl = {
                    type = "object",
                    properties = {
                        ssl_trusted_certificate = {
                            type = "string",
                        },
                        listen = {
                            type = "array",
                            items = {
                                type = "object",
                                properties = {
                                    ip = {
                                        type = "string",
                                    },
                                    port = {
                                        type = "integer",
                                        minimum = 1,
                                        maximum = 65535
                                    },
                                    enable_http2 = {
                                        type = "boolean",
                                    }
                                }
                            }
                        },
                        key_encrypt_salt = {
                            anyOf = {
                                {
                                    type = "array",
                                    minItems = 1,
                                    items = {
                                        type = "string",
                                        minLength = 16,
                                        maxLength = 16
                                    }
                                },
                                {
                                    type = "string",
                                    minLength = 16,
                                    maxLength = 16
                                }
                            }
                        },
                    }
                },
            }
        },
        enable_control = {
            type = "boolean",
        },
        control = {
            type = "object",
            properties = {
                ip = {
                    type = "string",
                },
                port = {
                    type = "integer",
                    minimum = 1,
                    maximum = 65535
                },
            }
        },
        data_encryption = {
            type = "object",
            properties = {
                enable = {
                    type = "boolean",
                },
                keyring = {
                    type = "array",
                    items = {
                        type = "string",
                    }
                },
            }
        },
        nginx_config = {
            type = "object",
            properties = {
                user = {
                    type = "string",
                },
                error_log = {
                    type = "string",
                },
                error_log_level = {
                    type = "string",
                    enum = { "info", "debug", "notice", "warn", "error", "crit", "alert", "emerg" }
                },
                worker_processes = {
                    anyOf = {
                        {
                            type = "integer",
                            minimum = 1,
                        },
                        {
                            type = "string"
                        },
                        {
                            type = "string",
                            enum = { "auto" }
                        }
                    }
                },
                enable_cpu_affinity = {
                    type = "boolean",
                },
                worker_rlimit_nofile = {
                    type = "integer",
                },
                worker_shutdown_timeout = {
                    type = "string",
                },
                max_pending_timers = {
                    type = "integer",
                },
                max_running_timers = {
                    type = "integer",
                },
                event = {
                    type = "object",
                    properties = {
                        worker_connections = {
                            type = "integer"
                        },
                    }
                },
                envs = {
                    type = "array",
                    minItems = 1,
                    items = {
                        type = "string",
                    }
                },
                meta = {
                    type = "object",
                    properties = {
                        lua_shared_dict = {
                            type = "object",
                        },
                    }
                },
                stream = {
                    type = "object",
                    properties = {
                        enable_access_log = {
                            type = "boolean",
                        },
                        access_log = {
                            type = "string",
                        },
                        access_log_format = {
                            type = "string",
                        },
                        access_log_format_escape = {
                            type = "string",
                        },
                        lua_shared_dict = {
                            type = "object",
                        },
                    }
                },
                main_configuration_snippet = {
                    type = "string"
                },
                http_configuration_snippet = {
                    type = "string"
                },
                http_server_configuration_snippet = {
                    type = "string"
                },
                http_server_location_configuration_snippet = {
                    type = "string"
                },
                http_admin_configuration_snippet = {
                    type = "string"
                },
                http_end_configuration_snippet = {
                    type = "string"
                },
                stream_configuration_snippet = {
                    type = "string"
                },
                http = {
                    type = "object",
                    properties = {
                        enable_access_log = {
                            type = "boolean"
                        },
                        access_log = {
                            type = "string"
                        },
                        access_log_buffer = {
                            type = "integer"
                        },
                        access_log_format = {
                            type = "string"
                        },
                        access_log_format_escape = {
                            type = "string"
                        },
                        keepalive_timeout = {
                            type = "string"
                        },
                        client_header_timeout = {
                            type = "string"
                        },
                        client_body_timeout = {
                            type = "string"
                        },
                        client_max_body_size = {
                            anyOf = {
                                {
                                    type = "number"
                                },
                                {
                                    type = "string"
                                }
                            }
                        },
                        send_timeout = {
                            type = "string"
                        },
                        underscores_in_headers = {
                            type = "string"
                        },
                        real_ip_header = {
                            type = "string"
                        },
                        real_ip_recursive = {
                            type = "string"
                        },
                        real_ip_from = {
                            type = "array",
                            items = {
                                type = "string"
                            }
                        },
                        custom_lua_shared_dict = {
                            type = "object"
                        },
                        proxy_ssl_server_name = {
                            type = "boolean"
                        },
                        upstream = {
                            type = "object",
                            properties = {
                                keepalive = {
                                    type = "integer"
                                },
                                keepalive_requests = {
                                    type = "integer"
                                },
                                keepalive_timeout = {
                                    type = "string"
                                }
                            }
                        },
                        charset = {
                            type = "string"
                        },
                        variables_hash_max_size = {
                            type = "integer"
                        },
                        lua_shared_dict = {
                            type = "object"
                        }
                    }
                }
            },
        },
        -- TODO: Add schema for discovery
        http = {
            type = "object",
            properties = {
                custom_lua_shared_dict = {
                    type = "object",
                }
            }
        },
        graphql = {
            type = "object",
            properties = {
                max_size = {
                    type = "integer"
                }
            }
        },
        etcd = etcd_schema,
        plugins = {
            type = "array",
            default = {},
            minItems = 0,
            items = {
                type = "string"
            }
        },
        stream_plugins = {
            type = "array",
            default = {},
            minItems = 0,
            items = {
                type = "string"
            }
        },
        wasm = {
            type = "object",
            properties = {
                plugins = {
                    type = "array",
                    minItems = 1,
                    items = {
                        type = "object",
                        properties = {
                            name = {
                                type = "string"
                            },
                            file = {
                                type = "string"
                            },
                            priority = {
                                type = "integer"
                            },
                            http_request_phase = {
                                enum = { "access", "rewrite" },
                                default = "access",
                            },
                        },
                        required = { "name", "file", "priority" }
                    }
                }
            }
        },
        plugin_attr = {
            type = "object"
        },
        deployment = {
            type = "object",
            properties = {
                role = {
                    enum = { "traditional", "control_plane", "data_plane", "standalone" },
                    default = "traditional"
                },
            },
            dependencies = {
                role = {
                    oneOf = {
                        {
                            properties = {
                                role = { const = "traditional" },
                                etcd = etcd_schema,
                                admin = admin_schema,
                                role_traditional = {
                                    type = "object",
                                    properties = {
                                        config_provider = {
                                            enum = { "etcd" }
                                        },
                                    },
                                    required = { "config_provider" }
                                },
                            },
                            required = { "role_traditional" },
                        },
                        {
                            properties = {
                                role = { const = "control_plane" },
                                etcd = etcd_schema,
                                admin = admin_schema,
                                role_control_plane = {
                                    type = "object",
                                    properties = {
                                        config_provider = {
                                            enum = { "etcd" }
                                        },
                                    },
                                    required = { "config_provider" }
                                },
                            },
                            required = { "role_control_plane" },
                        },
                        {
                            properties = {
                                role = { const = "data_plane" },
                                etcd = etcd_schema,
                                role_data_plane = {
                                    type = "object",
                                    properties = {
                                        config_provider = {
                                            enum = { "etcd", "yaml", "xds" }
                                        },
                                    },
                                    required = { "config_provider" }
                                },
                            },
                            required = { "role_data_plane" },
                        },
                    }
                }
            }
        },
    },
    required = { "apisix", "deployment" },
}

function _M.validate(yaml_conf)
    local validator = jsonschema.generate_validator(config_schema)
    local ok, err = validator(yaml_conf)
    if not ok then
        return false, "failed to validate config: " .. err
    end

    if yaml_conf.discovery then
        for kind, conf in pairs(yaml_conf.discovery) do
            local ok, schema = pcall(require, "apisix.discovery." .. kind .. ".schema")
            if ok then
                local validator = jsonschema.generate_validator(schema)
                local ok, err = validator(conf)
                if not ok then
                    return false, "invalid discovery " .. kind .. " configuration: " .. err
                end
            end
        end
    end

    return true
end

return _M
