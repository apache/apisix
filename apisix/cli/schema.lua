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
        use_grpc = {
            type = "boolean",
            -- TODO: set true by default in v3.2
            default = false,
        },
    },
    required = {"prefix", "host"}
}

local config_schema = {
    type = "object",
    properties = {
        apisix = {
            properties = {
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
                                        required = {"name", "memory_size"},
                                        maxProperties = 2,
                                    },
                                    {
                                        required = {"name", "memory_size", "disk_size",
                                            "disk_path", "cache_levels"},
                                    }
                                },
                            },
                            uniqueItems = true,
                        }
                    }
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
                                        required = {"addr"}
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
        nginx_config = {
            type = "object",
            properties = {
                envs = {
                    type = "array",
                    minItems = 1,
                    items = {
                        type = "string",
                    }
                }
            },
        },
        http = {
            type = "object",
            properties = {
                custom_lua_shared_dict = {
                    type = "object",
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
                                enum = {"access", "rewrite"},
                                default = "access",
                            },
                        },
                        required = {"name", "file", "priority"}
                    }
                }
            }
        },
        deployment = {
            type = "object",
            properties = {
                role = {
                    enum = {"traditional", "control_plane", "data_plane", "standalone"},
                    default = "traditional"
                }
            },
        },
    },
    required = {"apisix", "deployment"},
}

local admin_schema = {
    type = "object",
    properties = {
        admin_key = {
            type = "array",
            properties = {
                items = {
                    properties = {
                        name = {type = "string"},
                        key = {type = "string"},
                        role = {type = "string"},
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
    }
}

local deployment_schema = {
    traditional = {
        properties = {
            etcd = etcd_schema,
            admin = admin_schema,
            role_traditional = {
                properties = {
                    config_provider = {
                        enum = {"etcd"}
                    },
                },
                required = {"config_provider"}
            }
        },
        required = {"etcd"}
    },
    control_plane = {
        properties = {
            etcd = etcd_schema,
            admin = admin_schema,
            role_control_plane = {
                properties = {
                    config_provider = {
                        enum = {"etcd"}
                    },
                    conf_server = {
                        properties = {
                            listen = {
                                type = "string",
                                default = "0.0.0.0:9280",
                            },
                            cert = { type = "string" },
                            cert_key = { type = "string" },
                            client_ca_cert = { type = "string" },
                        },
                        required = {"cert", "cert_key"}
                    },
                },
                required = {"config_provider", "conf_server"}
            },
            certs = {
                properties = {
                    cert = { type = "string" },
                    cert_key = { type = "string" },
                    trusted_ca_cert = { type = "string" },
                },
                dependencies = {
                    cert = {
                        required = {"cert_key"},
                    },
                },
                default = {},
            },
        },
        required = {"etcd", "role_control_plane"}
    },
    data_plane = {
        properties = {
            role_data_plane = {
                properties = {
                    config_provider = {
                        enum = {"control_plane", "yaml", "xds"}
                    },
                },
                required = {"config_provider"}
            },
            certs = {
                properties = {
                    cert = { type = "string" },
                    cert_key = { type = "string" },
                    trusted_ca_cert = { type = "string" },
                },
                dependencies = {
                    cert = {
                        required = {"cert_key"},
                    },
                },
                default = {},
            },
        },
        required = {"role_data_plane"}
    }
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

    local role = yaml_conf.deployment.role
    local validator = jsonschema.generate_validator(deployment_schema[role])
    local ok, err = validator(yaml_conf.deployment)
    if not ok then
        return false, "invalid deployment " .. role .. " configuration: " .. err
    end

    return true
end


return _M
