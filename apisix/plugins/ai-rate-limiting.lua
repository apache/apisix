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
local require = require
local setmetatable = setmetatable
local ipairs = ipairs
local type = type
local pairs = pairs
local pcall = pcall
local load = load
local math_floor = math.floor
local core = require("apisix.core")
local limit_count = require("apisix.plugins.limit-count.init")

local plugin_name = "ai-rate-limiting"

local instance_limit_schema = {
    type = "object",
    properties = {
        name = {type = "string"},
        limit = {
            oneOf = {
                {type = "integer", minimum = 1},
                {type = "string"},
            },
        },
        time_window = {
            oneOf = {
                {type = "integer", minimum = 1},
                {type = "string"},
            },
        }
    },
    required = {"name", "limit", "time_window"}
}

local schema = {
    type = "object",
    properties = {
        limit = {
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
        show_limit_quota_header = {type = "boolean", default = true},
        limit_strategy = {
            type = "string",
            enum = {"total_tokens", "prompt_tokens", "completion_tokens", "expression"},
            default = "total_tokens",
            description = "The strategy to limit the tokens"
        },
        cost_expr = {
            type = "string",
            minLength = 1,
            description = "Lua arithmetic expression for dynamic token cost calculation. "
                .. "Variables are injected from the LLM API raw usage response fields. "
                .. "Missing variables default to 0. "
                .. "Only valid when limit_strategy is 'expression'. "
                .. "Example: input_tokens + cache_creation_input_tokens + output_tokens",
        },
        instances = {
            type = "array",
            items = instance_limit_schema,
            minItems = 1,
        },
        rejected_code = {
            type = "integer", minimum = 200, maximum = 599, default = 503
        },
        rejected_msg = {
            type = "string", minLength = 1
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
    },
    dependencies = {
        limit = {"time_window"},
        time_window = {"limit"}
    },
    oneOf = {
        {
            anyOf = {
                {
                    required = {"limit", "time_window"}
                },
                {
                    required = {"instances"}
                }
            }
        },
        {
            required = {"rules"},
        }
    }
}

local _M = {
    version = 0.1,
    priority = 1030,
    name = plugin_name,
    schema = schema
}

local limit_conf_cache = core.lrucache.new({
    ttl = 300, count = 512
})


-- safe math functions allowed in cost expressions
local expr_safe_env = {
    math = math,
    abs = math.abs,
    ceil = math.ceil,
    floor = math.floor,
    max = math.max,
    min = math.min,
}

local function compile_cost_expr(expr_str)
    local fn_code = "return " .. expr_str
    -- validate syntax by loading first
    local fn, err = load(fn_code, "cost_expr", "t", expr_safe_env)
    if not fn then
        return nil, err
    end
    return fn_code
end


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end
    if conf.limit_strategy == "expression" then
        if not conf.cost_expr or conf.cost_expr == "" then
            return false, "cost_expr is required when limit_strategy is 'expression'"
        end
        local _, compile_err = compile_cost_expr(conf.cost_expr)
        if compile_err then
            return false, "invalid cost_expr: " .. compile_err
        end
    end
    return true
end


local function transform_limit_conf(plugin_conf, instance_conf, instance_name)
    local limit_conf = {
        rejected_code = plugin_conf.rejected_code,
        rejected_msg = plugin_conf.rejected_msg,
        show_limit_quota_header = plugin_conf.show_limit_quota_header,

        -- we may expose those fields to ai-rate-limiting later
        policy = "local",
        key_type = "constant",
        allow_degradation = false,
        sync_interval = -1,
        limit_header = "X-AI-RateLimit-Limit",
        remaining_header = "X-AI-RateLimit-Remaining",
        reset_header = "X-AI-RateLimit-Reset",
    }
    if plugin_conf.rules and #plugin_conf.rules > 0 then
        limit_conf.rules = plugin_conf.rules
        limit_conf._meta = plugin_conf._meta
        return limit_conf
    end

    local key = plugin_name .. "#global"
    local limit = plugin_conf.limit
    local time_window = plugin_conf.time_window
    local name = instance_name or ""
    if instance_conf then
        name = instance_conf.name
        key = instance_conf.name
        limit = instance_conf.limit
        time_window = instance_conf.time_window
    end
    limit_conf._vid = key
    limit_conf.key = key
    limit_conf._meta = plugin_conf._meta
    limit_conf.count = limit
    limit_conf.time_window = time_window
    limit_conf.limit_header = "X-AI-RateLimit-Limit-" .. name
    limit_conf.remaining_header = "X-AI-RateLimit-Remaining-" .. name
    limit_conf.reset_header = "X-AI-RateLimit-Reset-" .. name
    return limit_conf
end


local function fetch_limit_conf_kvs(conf)
    local mt = {
        __index = function(t, k)
            if not conf.limit then
                return nil
            end

            local limit_conf = transform_limit_conf(conf, nil, k)
            t[k] = limit_conf
            return limit_conf
        end
    }
    local limit_conf_kvs = setmetatable({}, mt)
    local conf_instances = conf.instances or {}
    for _, limit_conf in ipairs(conf_instances) do
        limit_conf_kvs[limit_conf.name] = transform_limit_conf(conf, limit_conf)
    end
    return limit_conf_kvs
end


function _M.access(conf, ctx)
    local ai_instance_name = ctx.picked_ai_instance_name
    if not ai_instance_name then
        return
    end

    local limit_conf
    if conf.rules and #conf.rules > 0 then
        limit_conf = transform_limit_conf(conf)
    else
        local limit_conf_kvs = limit_conf_cache(conf, nil, fetch_limit_conf_kvs, conf)
        limit_conf = limit_conf_kvs[ai_instance_name]
    end
    if not limit_conf then
        return
    end
    local code, msg = limit_count.rate_limit(limit_conf, ctx, plugin_name, 1, true)
    ctx.ai_rate_limiting = code and true or false
    return code, msg
end


function _M.check_instance_status(conf, ctx, instance_name)
    if conf == nil then
        local plugins = ctx.plugins
        for i = 1, #plugins, 2 do
            if plugins[i]["name"] == plugin_name then
                conf = plugins[i + 1]
            end
        end
    end
    if not conf then
        return true
    end

    instance_name = instance_name or ctx.picked_ai_instance_name
    if not instance_name then
        return nil, "missing instance_name"
    end

    if type(instance_name) ~= "string" then
        return nil, "invalid instance_name"
    end

    local limit_conf_kvs = limit_conf_cache(conf, nil, fetch_limit_conf_kvs, conf)
    local limit_conf = limit_conf_kvs[instance_name]
    if not limit_conf then
        return true
    end

    local code, _ = limit_count.rate_limit(limit_conf, ctx, plugin_name, 1, true)
    if code then
        core.log.info("rate limit for instance: ", instance_name, " code: ", code)
        return false
    end
    return true
end


local function eval_cost_expr(conf_cost_expr, raw)
    local fn_code = "return " .. conf_cost_expr
    -- build environment: safe math + usage variables (missing vars default to 0)
    local env = setmetatable({}, {
        __index = function(_, k)
            local v = expr_safe_env[k]
            if v ~= nil then
                return v
            end
            return 0
        end
    })
    for k, v in pairs(raw) do
        if type(v) == "number" then
            env[k] = v
        end
    end
    local fn, err = load(fn_code, "cost_expr", "t", env)
    if not fn then
        return nil, "failed to compile cost_expr: " .. err
    end
    local ok, result = pcall(fn)
    if not ok then
        return nil, "failed to evaluate cost_expr: " .. result
    end
    if type(result) ~= "number" then
        return nil, "cost_expr must return a number, got: " .. type(result)
    end
    return math_floor(result + 0.5)
end

local function get_token_usage(conf, ctx)
    if conf.limit_strategy == "expression" then
        local raw = ctx.llm_raw_usage
        if not raw then
            return
        end
        local result, err = eval_cost_expr(conf.cost_expr, raw)
        if not result then
            core.log.error(err)
            return
        end
        return result
    end

    local usage = ctx.ai_token_usage
    if not usage then
        return
    end
    return usage[conf.limit_strategy]
end


function _M.log(conf, ctx)
    local instance_name = ctx.picked_ai_instance_name
    if not instance_name then
        return
    end

    if ctx.ai_rate_limiting then
        return
    end

    local used_tokens = get_token_usage(conf, ctx)
    if not used_tokens then
        core.log.error("failed to get token usage for llm service")
        return
    end

    core.log.info("instance name: ", instance_name, " used tokens: ", used_tokens)

    local limit_conf
    if conf.rules and #conf.rules > 0 then
        limit_conf = transform_limit_conf(conf)
    else
        local limit_conf_kvs = limit_conf_cache(conf, nil, fetch_limit_conf_kvs, conf)
        limit_conf = limit_conf_kvs[instance_name]
    end
    if limit_conf then
        limit_count.rate_limit(limit_conf, ctx, plugin_name, used_tokens)
    end
end


return _M
