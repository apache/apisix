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
local tonumber = tonumber
local type = type
local tostring = tostring
local redis_schema = require("apisix.utils.redis-schema")
local get_phase = ngx.get_phase
local math_floor = math.floor
local str_format = string.format

local NO_DELAYED_SYNC = -1
-- Redis counter storage-format version, passed into the Redis backends and
-- embedded into the counter key by util.redis_incoming. Bump it (v1 -> v2 ...)
-- whenever the stored format changes so new code never reads a pre-upgrade key
-- with the new meaning; old keys just expire via their own TTL.
local KEY_VERSION = "v1"
local policy_to_additional_properties = core.table.deepcopy(redis_schema.schema)

local limit_redis_cluster_new
local limit_redis_new
local limit_redis_sentinel_new
local limit_local_new
do
    local local_src = "apisix.plugins.limit-count.limit-count-local"
    limit_local_new = require(local_src).new

    local redis_src = "apisix.plugins.limit-count.limit-count-redis"
    limit_redis_new = require(redis_src).new

    local cluster_src = "apisix.plugins.limit-count.limit-count-redis-cluster"
    limit_redis_cluster_new = require(cluster_src).new

    local sentinel_src = "apisix.plugins.limit-count.limit-count-redis-sentinel"
    limit_redis_sentinel_new = require(sentinel_src).new
end
local group_conf_lru = core.lrucache.new({
    type = 'plugin',
})
local group_limit_lru = core.lrucache.new({type = 'plugin'})
local lrucache = core.lrucache.new({type = 'plugin', serial_creating = true})

policy_to_additional_properties["redis-sentinel"] = {
    properties = {
        redis_sentinels = {
            type = "array",
            minItems = 1,
            items = {
                type = "object",
                properties = {
                    host = {type = "string", minLength = 2},
                    port = {type = "integer", minimum = 1, maximum = 65535},
                },
                required = {"host", "port"},
                additionalProperties = false,
            },
        },
        redis_master_name = {type = "string", minLength = 1},
        redis_role = {
            type = "string",
            enum = {"master", "slave"},
            default = "master",
        },
        redis_connect_timeout = {type = "integer", minimum = 1, default = 1000},
        redis_read_timeout = {type = "integer", minimum = 1, default = 1000},
        redis_keepalive_timeout = {type = "integer", minimum = 1, default = 60000},
        redis_database = {type = "integer", minimum = 0, default = 0},
        redis_username = {type = "string", minLength = 1},
        redis_password = {type = "string", minLength = 0},
        sentinel_username = {type = "string", minLength = 1},
        sentinel_password = {type = "string", minLength = 0},
    },
    required = {"redis_sentinels", "redis_master_name"},
}

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
        window_type = {
            type = "string",
            enum = {"fixed", "sliding"},
            default = "fixed",
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
                    header_prefix = {
                        type = "string",
                        description = "prefix for rate limit headers"
                    },
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
            enum = {"local", "redis", "redis-cluster", "redis-sentinel"},
            default = "local",
        },
        allow_degradation = {type = "boolean", default = false},
        show_limit_quota_header = {type = "boolean", default = true},
        sync_interval = {
            type = "number",
            default = NO_DELAYED_SYNC,
        }
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
        ["else"] = {
            ["if"] = {
                properties = {
                    policy = {
                        enum = {"redis-sentinel"},
                    },
                },
            },
            ["then"] = policy_to_additional_properties["redis-sentinel"],
        }
    },
    encrypt_fields = {"redis_password", "sentinel_password"},
}

local schema_copy = core.table.deepcopy(schema)

local _M = {
    policy_to_additional_properties = policy_to_additional_properties,
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
        -- oneOf conflict: both count/time_window and rules are present
        if err and err:find("value should match only one schema", 1, true) then
            if (conf.count or conf.time_window) and conf.rules then
                return false, "count/time_window and rules cannot be specified at the same time"
            end
        end
        return false, err
    end

    if conf.rules and (conf.count or conf.time_window) then
        return false, "count/time_window and rules cannot be specified at the same time"
    end

    if conf.group and conf.rules then
        return false, "group and rules cannot be specified at the same time"
    end

    if conf.group then
        -- means that call by some plugin not support
        if conf._vid then
            return false, "group is not supported"
        end

        local fields = {}
        -- When the group field is configured,
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
                core.log.error("previous limit-count group ", prev_conf.group,
                            " conf: ", core.json.encode(prev_conf))
                core.log.error("current limit-count group ", conf.group,
                            " conf: ", core.json.encode(conf))
                return false, "group conf mismatched"
            end
        end
    end

    if conf.policy == "redis" or conf.policy == "redis-cluster" or
        conf.policy == "redis-sentinel"
    then
        if conf.sync_interval and conf.sync_interval ~= NO_DELAYED_SYNC then
            if conf.sync_interval < 0.1 then
                return false, "sync_interval should not be smaller than 0.1"
            end

            if type(conf.time_window) == "number" and conf.sync_interval >= conf.time_window then
                return false, "sync_interval should be smaller than time_window"
            end
        end
    end

    -- Each rule writes its own counter, but the runtime counter key is derived
    -- only from the resolved key (not the rule index/window). Two rules sharing
    -- the same key would therefore read/write the same counter, double-counting
    -- a request and polluting each other's window/TTL. Reject duplicates instead.
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
    core.log.info("create new ", plugin_name, " plugin instance",
        ", policy: ", conf.policy,
        ", window_type: ", conf.window_type,
        ", sync_interval: ", conf.sync_interval,
        ", rule: ", core.json.delay_encode(rule, true))

    if not conf.policy or conf.policy == "local" then
        return limit_local_new("plugin-" .. plugin_name, rule.count,
                               rule.time_window, conf.window_type)
    end

    if conf.policy == "redis" then
        return limit_redis_new("plugin-" .. plugin_name, rule.count, rule.time_window, conf,
                               KEY_VERSION)
    end

    if conf.policy == "redis-cluster" then
        return limit_redis_cluster_new("plugin-" .. plugin_name, rule.count,
                                       rule.time_window, conf, KEY_VERSION)
    end

    if conf.policy == "redis-sentinel" then
        return limit_redis_sentinel_new("plugin-" .. plugin_name, rule.count,
                                        rule.time_window, conf, KEY_VERSION)
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
        local original_value = value
        local err, _
        value, err, _ = core.utils.resolve_var(value, ctx.var)
        if err then
            return nil, "could not resolve var for value: " .. original_value .. ", err: " .. err
        end
        value = tonumber(value)
        if not value then
            return nil, "resolved value is not a number"
        end
        -- count/time_window must be positive integers, matching the schema
        if value <= 0 then
            return nil, "resolved value must be a positive number, got: " .. tostring(value)
        end
        if value ~= math_floor(value) then
            return nil, "resolved value must be an integer, got: " .. tostring(value)
        end
        -- LuaJIT doubles lose integer precision above 2^53
        if value > 9007199254740991 then
            return nil, "resolved value exceeds safe integer range (2^53-1), got: "
                        .. tostring(value)
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
    for index, rule in ipairs(conf.rules) do
        -- a rule keyed on a var absent for this request just doesn't apply
        local key, _, n_resolved = core.utils.resolve_var(rule.key, ctx.var)
        if n_resolved == 0 then
            goto CONTINUE
        end
        -- the rule applies, so an invalid count/time_window must reject, not
        -- silently skip it, else a client-controlled var could disable limiting
        local count, err = resolve_var(ctx, rule.count)
        if err then
            return nil, err
        end
        local time_window, err2 = resolve_var(ctx, rule.time_window)
        if err2 then
            return nil, err2
        end
        core.table.insert(rules, {
            count = count,
            time_window = time_window,
            key_type = "constant",
            key = key,
            header_prefix = rule.header_prefix or index,
        })

        ::CONTINUE::
    end
    return rules
end



local function construct_rate_limiting_headers(conf, rule, metadata)
    if rule.header_prefix then
        local base_limit = conf.limit_header or metadata.limit_header
        local base_remaining = conf.remaining_header or metadata.remaining_header
        local base_reset = conf.reset_header or metadata.reset_header
        -- Insert rule prefix before "RateLimit-" to preserve any custom header base
        -- e.g. "X-AI-RateLimit-Limit" + prefix "1" -> "X-AI-1-RateLimit-Limit"
        local prefix = tostring(rule.header_prefix)
        return {
            limit_header = base_limit:gsub("RateLimit%-", prefix .. "-RateLimit-", 1),
            remaining_header = base_remaining:gsub("RateLimit%-", prefix .. "-RateLimit-", 1),
            reset_header = base_reset:gsub("RateLimit%-", prefix .. "-RateLimit-", 1),
        }
    end
    return  {
        limit_header = conf.limit_header or metadata.limit_header,
        remaining_header = conf.remaining_header or metadata.remaining_header,
        reset_header = conf.reset_header or metadata.reset_header,
    }
end


local function run_rate_limit(conf, rule, ctx, name, cost, dry_run)
    local lim, err
    if conf.group then
        lim, err = group_limit_lru(conf.group, "", create_limit_obj, conf, conf, name)
    elseif not conf.rules
        and type(conf.count) == "number"
        and type(conf.time_window) == "number"
    then
        local key = name .. "#" .. (conf.policy or "local")
        if conf._vid then
            key = key .. "#" .. conf._vid
        end
        lim, err = core.lrucache.plugin_ctx(lrucache, ctx, key,
                                            create_limit_obj, conf, conf, name)
    else
        lim, err = create_limit_obj(conf, rule, name)
    end

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
    if not key then
        return 500
    end
    core.log.info("limit key: ", key, ", count: ", rule.count,
                  ", time_window: ", rule.time_window)

    local phase = get_phase()
    local is_log_phase = phase == "log"
    local commit_cost = dry_run and 0 or cost

    local delay, remaining, reset
    if not conf.policy or conf.policy == "local" then
        delay, remaining, reset = lim:incoming(key, commit_cost)
    else
        local enable_delayed_sync = conf.sync_interval and (conf.sync_interval ~= NO_DELAYED_SYNC)
        -- a dynamic time_window may resolve to a value <= sync_interval at request
        -- time, which would break delayed-sync semantics; fall back to direct sync
        if enable_delayed_sync and rule.time_window <= conf.sync_interval then
            enable_delayed_sync = false
        end
        if is_log_phase then
            lim:log_phase_incoming(key, commit_cost)
            return
        elseif enable_delayed_sync then
            local extra_key = name .. '#' .. conf.policy
            if conf._vid then
                extra_key = extra_key .. '#' .. conf._vid
            end
            local plugin_instance_id = core.lrucache.plugin_ctx_id(ctx, extra_key)
            delay, remaining, reset = lim:incoming_delayed(key, commit_cost, plugin_instance_id)
        else
            delay, remaining, reset = lim:incoming(key, commit_cost)
        end
    end

    if dry_run and type(remaining) == "number" and remaining - cost < 0 then
        delay = nil
        remaining = "rejected"
    end
    reset = reset and (math_floor(reset * 100) / 100)

    core.utils.set_var_rate_limiting_info(ctx, key, lim.limit, remaining, reset)

    local metadata = apisix_plugin.plugin_metadata(name)
    if metadata then
        metadata = metadata.value
    else
        metadata = metadata_defaults
    end
    core.log.info("limit-count plugin-metadata: ", core.json.delay_encode(metadata))

    local set_limit_headers = construct_rate_limiting_headers(conf, rule, metadata)
    local set_header = not is_log_phase

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
