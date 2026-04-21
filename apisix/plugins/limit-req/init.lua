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
local limit_req_new = require("resty.limit.req").new
local core = require("apisix.core")
local sleep = core.sleep
local tonumber = tonumber
local type = type
local tostring = tostring
local ipairs = ipairs
local error = error
local apisix_plugin = require("apisix.plugin")

local redis_single_new
local redis_cluster_new
do
    local redis_src = "apisix.plugins.limit-req.limit-req-redis"
    redis_single_new = require(redis_src).new

    local cluster_src = "apisix.plugins.limit-req.limit-req-redis-cluster"
    redis_cluster_new = require(cluster_src).new
end


local _M = {}


local function resolve_var(ctx, value)
    if type(value) == "string" then
        local err, _
        value, err, _ = core.utils.resolve_var(value, ctx.var)
        if err then
            return nil, "could not resolve var for value: " .. value .. ", err: " .. err
        end
        value = tonumber(value)
        if not value then
            return nil, "resolved value is not a number: " .. tostring(value)
        end
    end
    return value
end


local function get_rules(ctx, conf)
    if not conf.rules then
        local rate, err = resolve_var(ctx, conf.rate)
        if err then
            return nil, err
        end
        local burst, err2 = resolve_var(ctx, conf.burst)
        if err2 then
            return nil, err2
        end
        return {
            {
                rate = rate,
                burst = burst,
                key = conf.key,
                key_type = conf.key_type,
            }
        }
    end

    local rules = {}
    for _, rule in ipairs(conf.rules) do
        local rate, err = resolve_var(ctx, rule.rate)
        if err then
            goto CONTINUE
        end
        local burst, err2 = resolve_var(ctx, rule.burst)
        if err2 then
            goto CONTINUE
        end

        local key, _, n_resolved = core.utils.resolve_var(rule.key, ctx.var)
        if n_resolved == 0 then
            goto CONTINUE
        end
        core.table.insert(rules, {
            rate = rate,
            burst = burst,
            key_type = "constant",
            key = key,
        })

        ::CONTINUE::
    end
    return rules
end


local function create_limit_obj(conf, rule)
    core.log.info("create new limit-req plugin instance")

    local rate = rule.rate
    local burst = rule.burst

    core.log.info("limit req rate: ", rate, ", burst: ", burst)

    if conf.policy == "local" then
        core.log.info("create new limit-req plugin instance")
        return limit_req_new("plugin-limit-req", rate, burst)

    elseif conf.policy == "redis" then
        core.log.info("create new limit-req redis plugin instance")
        return redis_single_new("plugin-limit-req", conf, rate, burst)

    elseif conf.policy == "redis-cluster" then
        core.log.info("create new limit-req redis-cluster plugin instance")
        return redis_cluster_new("plugin-limit-req", conf, rate, burst)

    else
        return nil, "policy enum not match"
    end
end


local function gen_limit_key(conf, ctx, key)
    local parent = conf._meta and conf._meta.parent
    if not parent or not parent.resource_key then
        error("failed to generate key invalid parent: " .. core.json.encode(parent))
    end

    return parent.resource_key .. ':' .. apisix_plugin.conf_version(conf) .. ':' .. key
end


local function run_limit_req(conf, rule, ctx)
    local lim, err = create_limit_obj(conf, rule)
    if not lim then
        core.log.error("failed to instantiate a resty.limit.req object: ", err)
        if conf.allow_degradation then
            return
        end
        return 500
    end

    local conf_key = rule.key
    local key
    if rule.key_type == "var_combination" then
        local err, n_resolved
        key, err, n_resolved = core.utils.resolve_var(conf_key, ctx.var)
        if err then
            core.log.error("could not resolve vars in ", conf_key, " error: ", err)
        end

        if n_resolved == 0 then
            key = nil
        end
    elseif rule.key_type == "constant" then
        key = conf_key
    else
        key = ctx.var[conf_key]
    end

    if key == nil then
        core.log.info("The value of the configured key is empty, use client IP instead")
        key = ctx.var["remote_addr"]
    end

    key = gen_limit_key(conf, ctx, key)
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


function _M.rate_limit(conf, ctx)
    core.log.info("ver: ", ctx.conf_version)

    local rules, err = get_rules(ctx, conf)
    if not rules or #rules == 0 then
        core.log.error("failed to get limit req rules: ", err)
        if conf.allow_degradation then
            return
        end
        return 500
    end

    for _, rule in ipairs(rules) do
        local code, msg = run_limit_req(conf, rule, ctx)
        if code then
            return code, msg
        end
    end
end


return _M
