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

local policy_to_additional_properties = {
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
            redis_keepalive_timeout = {
                type = "integer", minimum = 1000, default = 10000
            },
            redis_keepalive_pool = {
                type = "integer", minimum = 1, default = 100
            }
        },
        required = {"redis_host"},
    },
    ["redis-cluster"] = {
        properties = {
            redis_cluster_nodes = {
                type = "array",
                minItems = 1,
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
            redis_keepalive_timeout = {
                type = "integer", minimum = 1000, default = 10000
            },
            redis_keepalive_pool = {
                type = "integer", minimum = 1, default = 100
            }
        },
        required = {"redis_cluster_nodes", "redis_cluster_name"},
    },
}

local limit_conn_redis_cluster_schema = policy_to_additional_properties["redis-cluster"]
limit_conn_redis_cluster_schema.properties.key_ttl = {
    type = "integer", default = 3600,
}

local limit_conn_redis_schema = policy_to_additional_properties["redis"]
limit_conn_redis_schema.properties.key_ttl = {
    type = "integer", default = 3600,
}

local _M = {
    schema = policy_to_additional_properties,
    limit_conn_redis_cluster_schema = limit_conn_redis_cluster_schema,
    limit_conn_redis_schema = limit_conn_redis_schema,
}

return _M
