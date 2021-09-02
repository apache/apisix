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
local core          = require("apisix.core")
local limit_local_new = require("resty.limit.count").new
local plugin_name   = "proxy-mirror"
local limit_redis_cluster_new
local limit_redis_new
do
    local redis_src = "apisix.plugins.limit-count.limit-count-redis"
    limit_redis_new = require(redis_src).new

    local cluster_src = "apisix.plugins.limit-count.limit-count-redis-cluster"
    limit_redis_cluster_new = require(cluster_src).new
end
local lrucache = core.lrucache.new({
    type = 'plugin', serial_creating = true,
})

local schema = {
    type = "object",
    properties = {
        host = {
            type = "string",
            pattern = [[^http(s)?:\/\/[a-zA-Z0-9][-a-zA-Z0-9]{0,62}]]
                      .. [[(\.[a-zA-Z0-9][-a-zA-Z0-9]{0,62})+(:[0-9]{1,5})?$]],
        },
        count = { type = "integer", minimum = 1, default = 1 },
        time_window = { type = "integer", minimum = 1, default = 60 },
        policy = {
            type = "string",
            enum = { "local", "redis", "redis-cluster" },
            default = "local",
        },
        enable_limit_count = { type = "boolean", default = false },
    },
    required = {"host"},
    minProperties = 1,
    dependencies = {
        policy = {
            oneOf = {
                {
                    properties = {
                        policy = {
                            enum = {"local"},
                        },
                    },
                },
                {
                    properties = {
                        policy = {
                            enum = {"redis"},
                        },
                        redis_host = {
                            type = "string", minLength = 2,
                        },
                        redis_port = {
                            type = "integer", minimum = 1, default = 6379,
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
                    },
                    required = {"redis_host"},
                },
                {
                    properties = {
                        policy = {
                            enum = {"redis-cluster"},
                        },
                        redis_cluster_nodes = {
                            type = "array",
                            minItems = 2,
                            items = {
                                type = "string", minLength = 2, maxLength = 100,
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
                    },
                    required = {"redis_cluster_nodes", "redis_cluster_name"},
                }
            }
        }
    }
}

local _M = {
    version = 0.1,
    priority = 1010,
    name = plugin_name,
    schema = schema,
}


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    return true
end

local function create_limit_obj(conf)
    core.log.info("create new limit count object instance")

    if not conf.policy or conf.policy == "local" then
        return limit_local_new("plugin-" .. plugin_name, conf.count,
            conf.time_window)
    end

    if conf.policy == "redis" then
        return limit_redis_new("plugin-" .. plugin_name,
            conf.count, conf.time_window, conf)
    end

    if conf.policy == "redis-cluster" then
        return limit_redis_cluster_new("plugin-" .. plugin_name, conf.count,
            conf.time_window, conf)
    end

    return nil
end

function _M.rewrite(conf, ctx)
    core.log.info("proxy mirror plugin rewrite phase, conf: ", core.json.delay_encode(conf))

    ctx.var.upstream_host = ctx.var.host

    local is_mirror_request = true
    if conf.enable_limit_count then
        local lim, err = core.lrucache.plugin_ctx(lrucache, ctx, conf.policy,
            create_limit_obj, conf)
        if not lim then
            core.log.error("failed to fetch limit count object: ", err)
        else
            local key = ctx.conf_type .. ctx.conf_version
            core.log.info("limit key: ", key)

            local delay, remaining = lim:incoming(key, true)
            if not delay then
                local err = remaining
                if err == "rejected" then
                    is_mirror_request = false
                else
                    core.log.error("failed to limit mirror request: ", err)
                end
            end
        end
    end

    if is_mirror_request then
        ctx.var.upstream_mirror_host = conf.host
    end
end


return _M
