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
local apisix_plugin = require("apisix.plugin")
local tab_insert = table.insert
local ipairs = ipairs
local pairs = pairs
local redis_schema = require("apisix.utils.redis-schema")
local policy_to_additional_properties = redis_schema.schema
local get_phase = ngx.get_phase
local tonumber = tonumber
local type = type
local tostring = tostring
local str_format = string.format

local limit_redis_cluster_new
local limit_redis_new
local limit_local_new
do
    local local_src = "apisix.plugins.limit-count.limit-count-local"
    limit_local_new = require(local_src).new

    local redis_src = "apisix.plugins.limit-count.limit-count-redis"
    limit_redis_new = require(redis_src).new

    local cluster_src = "apisix.plugins.limit-count.limit-count-redis-cluster"
    limit_redis_cluster_new = require(cluster_src).new
end
local group_conf_lru = core.lrucache.new({
    type = 'plugin',
})

local metadata_defaults = {
    limit_header = "X-RateLimit-Limit",
    remaining_header = "X-RateLimit-Remaining",
    reset_header = "X-RateLimit-Reset",
}

local metadata_schema = {
    type = "object",
    properties = {
        limit_header = {
            type = "string",
            default = metadata_defaults.limit_header,
        },
        remaining_header = {
            type = "string",
            default = metadata_defaults.remaining_header,
        },
        reset_header = {
            type = "string",
            default = metadata_defaults.reset_header,
        },
    },
}

local schema = {
    type = "object",
    properties = {
        count = {
            oneOf = {
                {type = "integer", exclusiveMinimum = 0},
                {type = "string"},
            },
        },
        time_window = {
            oneOf = {
                {type = "integer", exclusiveMinimum = 0},
                {type = "string"},
            },
        },
        rules = {
            type = "array",
            items = {
                type = "object",
                properties = {
                    count = {
                        oneOf = {
                            {type = "integer", exclusiveMinimum = 0},
                            {type = "string"},
                        },
                    },
                    time_window = {
                        oneOf = {
                            {type = "integer", exclusiveMinimum = 0},
                            {type = "string"},
                        },
                    },
                    key = {type = "string"},
                },
                required = {"count", "time_window", "key"},
            },
        },
        group = {type = "string"},
        key = {type = "string", default = "remote_addr"},
        key_type = {type = "string",
            enum = {"var", "var_combination", "constant"},
            default = "var",
        },
        rejected_code = {
            type = "integer", minimum = 200, maximum = 599, default = 503
        },
        rejected_msg = {
            type = "string", minLength = 1
        },
        policy = {
            type = "string",
            enum = {"local", "redis", "redis-cluster"},
            default = "local",
        },
        allow_degradation = {type = "boolean", default = false},
        show_limit_quota_header = {type = "boolean", default = true}
    },
    oneOf = {
        {
            required = {"count", "time_window"},
        },
        {
            required = {"rules"},
        }
    },
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

local schema_copy = core.table.deepcopy(schema)

local _M = {
    schema = schema,
    metadata_schema = metadata_schema,
}


local function group_conf(conf)
    return conf
end



function _M.check_schema(conf, schema_type)
    if schema_type == core.schema.TYPE_METADATA then
        return core.schema.check(metadata_schema, conf)
    end

    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    if conf.group then
        -- means that call by some plugin not support
        if conf._vid then
            return false, "group is not supported"
        end

        local fields = {}
        -- When the goup field is configured,
        -- we will use schema_copy to get the whitelist of properties,
        -- so that we can avoid getting injected properties.
        for k in pairs(schema_copy.properties) do
            tab_insert(fields, k)
        end
        local extra = policy_to_additional_properties[conf.policy]
        if extra then
            for k in pairs(extra.properties) do
                tab_insert(fields, k)
            end
        end

        local prev_conf = group_conf_lru(conf.group, "", group_conf, conf)

        for _, field in ipairs(fields) do
            if not core.table.deep_eq(prev_conf[field], conf[field]) then
                core.log.error("previous limit-conn group ", prev_conf.group,
                            " conf: ", core.json.encode(prev_conf))
                core.log.error("current limit-conn group ", conf.group,
                            " conf: ", core.json.encode(conf))
                return false, "group conf mismatched"
            end
        end
    end

    local keys = {}
    for _, rule in ipairs(conf.rules or {}) do
        if keys[rule.key] then
            return false, str_format("duplicate key '%s' in rules", rule.key)
        end
        keys[rule.key] = true
    end

    return true
end


local function create_limit_obj(conf, rule, plugin_name)
    core.log.info("create new " .. plugin_name .. " plugin instance",
        ", rule: ", core.json.delay_encode(rule, true))

    if not conf.policy or conf.policy == "local" then
        return limit_local_new("plugin-" .. plugin_name, rule.count,
                               rule.time_window)
    end

    if conf.policy == "redis" then
        return limit_redis_new("plugin-" .. plugin_name, rule.count, rule.time_window, conf)
    end

    if conf.policy == "redis-cluster" then
        return limit_redis_cluster_new("plugin-" .. plugin_name, rule.count,
                                       rule.time_window, conf)
    end

    return nil
end


local function gen_limit_key(conf, ctx, key)
    if conf.group then
        return conf.group .. ':' .. key
    end

    -- here we add a separator ':' to mark the boundary of the prefix and the key itself
    -- Here we use plugin-level conf version to prevent the counter from being resetting
    -- because of the change elsewhere.
    -- A route which reuses a previous route's ID will inherits its counter.
    local parent = conf._meta and conf._meta.parent
    if not parent or not parent.resource_key then
        core.log.error("failed to generate key invalid parent: ", core.json.encode(parent))
        return nil
    end

    local new_key = parent.resource_key .. ':' .. apisix_plugin.conf_version(conf)
                    .. ':' .. key
    if conf._vid then
        -- conf has _vid means it's from workflow plugin, add _vid to the key
        -- so that the counter is unique per action.
        return new_key .. ':' .. conf._vid
    end

    return new_key
end


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
        local count, err = resolve_var(ctx, conf.count)
        if err then
            return nil, err
        end
        local time_window, err2 = resolve_var(ctx, conf.time_window)
        if err2 then
            return nil, err2
        end
        return {
            {
                count = count,
                time_window = time_window,
                key = conf.key,
                key_type = conf.key_type,
            }
        }
    end

    local rules = {}
    for _, rule in ipairs(conf.rules) do
        local count, err = resolve_var(ctx, rule.count)
        if err then
            goto CONTINUE
        end
        local time_window, err2 = resolve_var(ctx, rule.time_window)
        if err2 then
            goto CONTINUE
        end
        local key, _, n_resolved = core.utils.resolve_var(rule.key, ctx.var)
        if n_resolved == 0 then
            goto CONTINUE
        end
        core.table.insert(rules, {
            count = count,
            time_window = time_window,
            key_type = "constant",
            key = key,
        })

        ::CONTINUE::
    end
    return rules
end


local function run_rate_limit(conf, rule, ctx, name, cost, dry_run)
    local lim, err = create_limit_obj(conf, rule, name)

    if not lim then
        core.log.error("failed to fetch limit.count object: ", err)
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

    key = gen_limit_key(conf, ctx, key)
    core.log.info("limit key: ", key)

    local delay, remaining, reset
    if not conf.policy or conf.policy == "local" then
        delay, remaining, reset = lim:incoming(key, not dry_run, conf, cost)
    else
        delay, remaining, reset = lim:incoming(key, cost)
    end

    local metadata = apisix_plugin.plugin_metadata("limit-count")
    if metadata then
        metadata = metadata.value
    else
        metadata = metadata_defaults
    end
    core.log.info("limit-count plugin-metadata: ", core.json.delay_encode(metadata))

    local set_limit_headers = {
        limit_header = conf.limit_header or metadata.limit_header,
        remaining_header = conf.remaining_header or metadata.remaining_header,
        reset_header = conf.reset_header or metadata.reset_header,
    }
    local phase = get_phase()
    local set_header = phase ~= "log"

    if not delay then
        local err = remaining
        if err == "rejected" then
            -- show count limit header when rejected
            if conf.show_limit_quota_header and set_header then
                core.response.set_header(set_limit_headers.limit_header, lim.limit,
                set_limit_headers.remaining_header, 0,
                set_limit_headers.reset_header, reset)
            end

            if conf.rejected_msg then
                return conf.rejected_code, { error_msg = conf.rejected_msg }
            end
            return conf.rejected_code
        end

        core.log.error("failed to limit count: ", err)
        if conf.allow_degradation then
            return
        end
        return 500, {error_msg = "failed to limit count"}
    end

    if conf.show_limit_quota_header and set_header then
        core.response.set_header(set_limit_headers.limit_header, lim.limit,
            set_limit_headers.remaining_header, remaining,
            set_limit_headers.reset_header, reset)
    end
end


function _M.rate_limit(conf, ctx, name, cost, dry_run)
    core.log.info("ver: ", ctx.conf_version)

    local rules, err = get_rules(ctx, conf)
    if not rules or #rules == 0 then
        core.log.error("failed to get rate limit rules: ", err)
        if conf.allow_degradation then
            return
        end
        return 500
    end

    for _, rule in ipairs(rules) do
        local code, msg = run_rate_limit(conf, rule, ctx, name, cost, dry_run)
        if code then
            return code, msg
        end
    end
end


return _M
