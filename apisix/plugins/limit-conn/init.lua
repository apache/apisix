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
local limit_conn_new = require("resty.limit.conn").new
local core = require("apisix.core")
local is_http = ngx.config.subsystem == "http"
local sleep = core.sleep
local tonumber = tonumber
local type = type
local tostring = tostring
local shdict_name = "plugin-limit-conn"
if ngx.config.subsystem == "stream" then
    shdict_name = shdict_name .. "-stream"
end

local redis_single_new
local redis_cluster_new
do
    local redis_src = "apisix.plugins.limit-conn.limit-conn-redis"
    redis_single_new = require(redis_src).new

    local cluster_src = "apisix.plugins.limit-conn.limit-conn-redis-cluster"
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
        local conn, err = resolve_var(ctx, conf.conn)
        if err then
            return nil, err
        end
        local burst, err2 = resolve_var(ctx, conf.burst)
        if err2 then
            return nil, err2
        end
        return {
            {
                conn = conn,
                burst = burst,
                key = conf.key,
                key_type = conf.key_type,
            }
        }
    end

    local rules = {}
    for _, rule in ipairs(conf.rules) do
        local conn, err = resolve_var(ctx, rule.conn)
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
            conn = conn,
            burst = burst,
            key_type = "constant",
            key = key,
        })

        ::CONTINUE::
    end
    return rules
end


local function create_limit_obj(conf, rule, default_conn_delay)
    core.log.info("create new limit-conn plugin instance")

    local conn = rule.conn
    local burst = rule.burst

    core.log.info("limit conn: ", conn, ", burst: ", burst)

    if conf.policy == "redis" then
        core.log.info("create new limit-conn redis plugin instance")

        return redis_single_new("plugin-limit-conn", conf, conn, burst,
                                default_conn_delay)

    elseif conf.policy == "redis-cluster" then

        core.log.info("create new limit-conn redis-cluster plugin instance")

        return redis_cluster_new("plugin-limit-conn", conf, conn, burst,
                                 default_conn_delay)
    else
        core.log.info("create new limit-conn plugin instance")
        return limit_conn_new(shdict_name, conn, burst,
                              default_conn_delay)
    end
end


local function run_limit_conn(conf, rule, ctx)
    local lim, err = create_limit_obj(conf, rule, conf.default_conn_delay)
    if not lim then
        core.log.error("failed to instantiate a resty.limit.conn object: ", err)
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
            return conf.rejected_code or 503
        end

        core.log.error("failed to limit conn: ", err)
        if conf.allow_degradation then
            return
        end
        return 500
    end

    if lim:is_committed() then
        if not ctx.limit_conn then
            ctx.limit_conn = core.tablepool.fetch("plugin#limit-conn", 0, 6)
        end

        core.table.insert_tail(ctx.limit_conn, lim, key, delay, conf.only_use_default_delay)
    end

    if delay >= 0.001 then
        sleep(delay)
    end
end


function _M.increase(conf, ctx)
    core.log.info("ver: ", ctx.conf_version)

    local rules, err = get_rules(ctx, conf)
    if not rules or #rules == 0 then
        core.log.error("failed to get limit conn rules: ", err)
        if conf.allow_degradation then
            return
        end
        return 500
    end

    for _, rule in ipairs(rules) do
        local code, msg = run_limit_conn(conf, rule, ctx)
        if code then
            return code, msg
        end
    end
end


function _M.decrease(conf, ctx)
    local limit_conn = ctx.limit_conn
    if not limit_conn then
        return
    end

    for i = 1, #limit_conn, 4 do
        local lim = limit_conn[i]
        local key = limit_conn[i + 1]
        local delay = limit_conn[i + 2]
        local use_delay =  limit_conn[i + 3]

        local latency
        if is_http then
            if not use_delay then
                if ctx.proxy_passed then
                    latency = ctx.var.upstream_response_time
                else
                    latency = ctx.var.request_time - delay
                end
            end
        end
        core.log.debug("request latency is ", latency) -- for test

        local conn, err = lim:leaving(key, latency)
        if not conn then
            core.log.error("failed to record the connection leaving request: ",
                           err)
            break
        end
    end

    core.tablepool.release("plugin#limit-conn", limit_conn)
    ctx.limit_conn = nil
    return
end


return _M
