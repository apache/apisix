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
local limit_req_new                     = require("resty.limit.req").new
local core                              = require("apisix.core")
local redis_schema                      = require("apisix.utils.redis-schema")
local policy_to_additional_properties   = redis_schema.schema
local plugin_name                       = "limit-req"
local sleep = core.sleep

local redis_single_new
local redis_cluster_new
do
    local redis_src = "apisix.plugins.limit-req.limit-req-redis"
    redis_single_new = require(redis_src).new

    local cluster_src = "apisix.plugins.limit-req.limit-req-redis-cluster"
    redis_cluster_new = require(cluster_src).new
end


local lrucache = core.lrucache.new({
    type = "plugin",
})


local schema = {
    type = "object",
    properties = {
        rate = {type = "number", exclusiveMinimum = 0},
        burst = {type = "number",  minimum = 0},
        key = {type = "string"},
        key_type = {type = "string",
            enum = {"var", "var_combination"},
            default = "var",
        },
        policy = {
            type = "string",
            enum = {"redis", "redis-cluster", "local"},
            default = "local",
        },
        rejected_code = {
            type = "integer", minimum = 200, maximum = 599, default = 503
        },
        rejected_msg = {
            type = "string", minLength = 1
        },
        nodelay = {
            type = "boolean", default = false
        },
        allow_degradation = {type = "boolean", default = false}
    },
    required = {"rate", "burst", "key"},
    ["if"] = {
        properties = {
            policy = {
                enum = {"redis"},
            },
        },
    },
    ["then"] = policy_to_additional_properties.redis,
    ["else"] = {
        ["if"] = {
            properties = {
                policy = {
                    enum = {"redis-cluster"},
                },
            },
        },
        ["then"] = policy_to_additional_properties["redis-cluster"],
    }
}


local _M = {
    version = 0.1,
    priority = 1001,
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
    if conf.policy == "local" then
        core.log.info("create new limit-req plugin instance")
        return limit_req_new("plugin-limit-req", conf.rate, conf.burst)

    elseif conf.policy == "redis" then
        core.log.info("create new limit-req redis plugin instance")
        return redis_single_new("plugin-limit-req", conf, conf.rate, conf.burst)

    elseif conf.policy == "redis-cluster" then
        core.log.info("create new limit-req redis-cluster plugin instance")
        return redis_cluster_new("plugin-limit-req", conf, conf.rate, conf.burst)

    else
        return nil, "policy enum not match"
    end
end


function _M.access(conf, ctx)
    local lim, err = core.lrucache.plugin_ctx(lrucache, ctx, nil,
                                              create_limit_obj, conf)
    if not lim then
        core.log.error("failed to instantiate a resty.limit.req object: ", err)
        if conf.allow_degradation then
            return
        end
        return 500
    end

    local conf_key = conf.key
    local key
    if conf.key_type == "var_combination" then
        local err, n_resolved
        key, err, n_resolved = core.utils.resolve_var(conf_key, ctx.var)
        if err then
            core.log.error("could not resolve vars in ", conf_key, " error: ", err)
        end

        if n_resolved == 0 then
            key = nil
        end

    else
        key = ctx.var[conf_key]
    end

    if key == nil then
        core.log.info("The value of the configured key is empty, use client IP instead")
        -- When the value of key is empty, use client IP instead
        key = ctx.var["remote_addr"]
    end

    key = key .. ctx.conf_type .. ctx.conf_version
    core.log.info("limit key: ", key)

    local delay, err = lim:incoming(key, true)
    if not delay then
        if err == "rejected" then
            if conf.rejected_msg then
                return conf.rejected_code, { error_msg = conf.rejected_msg }
            end
            return conf.rejected_code
        end

        core.log.error("failed to limit req: ", err)
        if conf.allow_degradation then
            return
        end
        return 500
    end

    if delay >= 0.001 and not conf.nodelay then
        sleep(delay)
    end
end

return _M
