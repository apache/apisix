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
local core = require("apisix.core")
local limit_conn = require("apisix.plugins.limit-conn.init")


local plugin_name = "limit-conn"

local redis_type_to_additional_properties = {
    redis = {
        properties = {
            redis_host = {
                type = "string", minLength = 2
            },
            redis_port = {
                type = "integer", minimum = 1, default = 6379,
            },
            redis_username = {
                type = "string", minLength = 1,
            },
            redis_password = {
                type = "string", minLength = 0,
            },
            redis_database = {
                type = "integer", minimum = 0, default = 0,
            },
            redis_timeout = {
                type = "integer", minimum = 1, default = 1000,
            },
            redis_ssl = {
                type = "boolean", default = false,
            },
            redis_ssl_verify = {
                type = "boolean", default = false,
            },
        },
        required = {"redis_host"},
    },
    ["redis-cluster"] = {
        properties = {
            redis_cluster_nodes = {
                type = "array",
                minItems = 2,
                items = {
                    type = "string", minLength = 2, maxLength = 100
                },
            },
            redis_password = {
                type = "string", minLength = 0,
            },
            redis_timeout = {
                type = "integer", minimum = 1, default = 1000,
            },
            redis_cluster_name = {
                type = "string",
            },
            redis_cluster_ssl = {
                type = "boolean", default = false,
            },
            redis_cluster_ssl_verify = {
                type = "boolean", default = false,
            },
            dict_name = {
                type = "string", minLength = 1,
            },
        },
        required = {"redis_cluster_nodes", "redis_cluster_name", "dict_name"},
    },
}
local schema = {
    type = "object",
    properties = {
        conn = {type = "integer", exclusiveMinimum = 0},               -- limit.conn max
        burst = {type = "integer",  minimum = 0},
        default_conn_delay = {type = "number", exclusiveMinimum = 0},
        only_use_default_delay = {type = "boolean", default = false},
        key = {type = "string"},
        key_type = {type = "string",
            enum = {"var", "var_combination"},
            default = "var",
        },
        redis_type = {
            type = "string",
            enum = {"redis", "redis-cluster"},
            default = "redis",
        },
        counter_type = {
            type = "string",
            enum = {"redis", "shared-dict"},
            default = "shared-dict",
        },
        rejected_code = {
            type = "integer", minimum = 200, maximum = 599, default = 503
        },
        rejected_msg = {
            type = "string", minLength = 1
        },
        allow_degradation = {type = "boolean", default = false}
    },
    required = {"conn", "burst", "default_conn_delay", "key"},
    ["if"] = {
        properties = {
            redis_type = {
                enum = {"redis"},
            },
        },
    },
    ["then"] = redis_type_to_additional_properties.redis,
    ["else"] = {
        ["if"] = {
            properties = {
                redis_type = {
                    enum = {"redis-cluster"},
                },
            },
        },
        ["then"] = redis_type_to_additional_properties["redis-cluster"],
    }
}

local _M = {
    version = 0.1,
    priority = 1003,
    name = plugin_name,
    schema = schema,
}


function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end


function _M.access(conf, ctx)
    return limit_conn.increase(conf, ctx)
end


function _M.log(conf, ctx)
    return limit_conn.decrease(conf, ctx)
end


return _M
