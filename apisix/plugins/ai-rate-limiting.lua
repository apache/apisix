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
local rawget = rawget
local rawset = rawset
local pcall = pcall
local load = load
local math_floor = math.floor
local math_huge = math.huge
local table_sort = table.sort
local table_concat = table.concat
local str_find = string.find
local str_sub = string.sub
local str_gsub = string.gsub
local str_gmatch = string.gmatch
local core = require("apisix.core")
local limit_count = require("apisix.plugins.limit-count.init")
local policy_to_additional_properties = limit_count.policy_to_additional_properties

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
        policy = {
            type = "string",
            enum = {"local", "redis", "redis-cluster", "redis-sentinel"},
            default = "local",
        },
        allow_degradation = {type = "boolean", default = false},
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
                properties = { policy = { enum = { "redis-sentinel" } } },
            },
            ["then"] = policy_to_additional_properties["redis-sentinel"],
        },
    },
    encrypt_fields = {"redis_password", "sentinel_password"},
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

local cost_expr_cache = core.lrucache.new({
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

local lua_keywords = {
    ["and"] = true, ["break"] = true, ["do"] = true, ["else"] = true,
    ["elseif"] = true, ["end"] = true, ["false"] = true, ["for"] = true,
    ["function"] = true, ["goto"] = true, ["if"] = true, ["in"] = true,
    ["local"] = true, ["nil"] = true, ["not"] = true, ["or"] = true,
    ["repeat"] = true, ["return"] = true, ["then"] = true, ["true"] = true,
    ["until"] = true, ["while"] = true,
}

-- private keys, unreachable from the expression
local RAW_KEY = {}
local PATHS_KEY = {}


local function walk_path(raw, segs)
    local v = raw
    for i = 1, #segs do
        if type(v) ~= "table" then
            return 0
        end
        v = v[segs[i]]
    end
    if type(v) == "number" then
        return v
    end
    return 0
end


-- search level by level; a clash on one level charges the larger value
local function find_leaf(raw, name)
    local v = raw[name]
    if type(v) == "number" then
        return v
    end

    local level, prefixes = {raw}, {""}
    while true do
        local best, hits = nil, 0
        for i = 1, #level do
            for k, tab in pairs(level[i]) do
                if type(k) == "string" and type(tab) == "table" then
                    local x = tab[name]
                    if type(x) == "number" then
                        hits = hits + 1
                        if not best or x > best then
                            best = x
                        end
                    end
                end
            end
        end

        if best then
            if hits > 1 then
                local paths = {}
                for i = 1, #level do
                    for k, tab in pairs(level[i]) do
                        if type(k) == "string" and type(tab) == "table"
                           and type(tab[name]) == "number" then
                            paths[#paths + 1] = prefixes[i] .. k .. "." .. name
                        end
                    end
                end
                table_sort(paths)
                core.log.error("ambiguous usage field '", name, "' in cost_expr matches ",
                               table_concat(paths, ", "), ", charging the larger value, ",
                               "use an explicit path instead")
            end
            return best
        end

        local next_level, next_prefixes = {}, {}
        for i = 1, #level do
            for k, tab in pairs(level[i]) do
                if type(k) == "string" and type(tab) == "table" then
                    next_level[#next_level + 1] = tab
                    next_prefixes[#next_prefixes + 1] = prefixes[i] .. k .. "."
                end
            end
        end
        if #next_level == 0 then
            return 0
        end
        level, prefixes = next_level, next_prefixes
    end
end


local usage_mt = {
    __index = function(t, k)
        local segs = rawget(t, PATHS_KEY)[k]
        local v
        if segs then
            v = walk_path(rawget(t, RAW_KEY), segs)
        else
            v = find_leaf(rawget(t, RAW_KEY), k)
        end
        rawset(t, k, v)
        return v
    end
}


-- rewrite usage names to reads on the `usage` argument
local function compile_cost_expr(expr_str)
    local paths = {}
    local bad_name
    local code = str_gsub(expr_str, "()([%a_][%w_%.]*)", function(pos, name)
        -- skip number literals like 1e5 or 0x1F
        if pos > 1 and str_find(str_sub(expr_str, pos - 1, pos - 1), "[%w_%.]") then
            return nil
        end
        local head = str_gsub(name, "%..*", "")
        if lua_keywords[name] or expr_safe_env[head] then
            return nil
        end
        if str_find(name, ".", 1, true) then
            if str_find(name, "..", 1, true) or str_sub(name, -1) == "." then
                bad_name = bad_name or name
                return nil
            end
            local segs = {}
            for seg in str_gmatch(name, "[^%.]+") do
                segs[#segs + 1] = seg
            end
            paths[name] = segs
        end
        return 'usage["' .. name .. '"]'
    end)
    if bad_name then
        return nil, "invalid field reference: " .. bad_name
    end

    -- own env per expression so writes stay local to it
    local env = setmetatable({}, {__index = expr_safe_env})
    local fn, err = load("local usage = ...\nreturn " .. code, "cost_expr", "t", env)
    if not fn then
        return nil, err
    end
    return {fn = fn, paths = paths}
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
        _meta = plugin_conf._meta,
        rejected_code = plugin_conf.rejected_code,
        rejected_msg = plugin_conf.rejected_msg,
        show_limit_quota_header = plugin_conf.show_limit_quota_header,

        -- counters can be shared across nodes via redis policies
        policy = plugin_conf.policy or "local",
        key_type = "constant",
        allow_degradation = plugin_conf.allow_degradation,
        sync_interval = -1,
        limit_header = "X-AI-RateLimit-Limit",
        remaining_header = "X-AI-RateLimit-Remaining",
        reset_header = "X-AI-RateLimit-Reset",
    }
    local name = instance_name or ""
    if plugin_conf.rules and #plugin_conf.rules > 0 then
        limit_conf.rules = plugin_conf.rules
    else
        local key = plugin_name .. "#global"
        local limit = plugin_conf.limit
        local time_window = plugin_conf.time_window
        if instance_conf then
            name = instance_conf.name
            key = instance_conf.name
            limit = instance_conf.limit
            time_window = instance_conf.time_window
        end
        limit_conf._vid = key
        limit_conf.key = key
        limit_conf.count = limit
        limit_conf.time_window = time_window
        limit_conf.limit_header = "X-AI-RateLimit-Limit-" .. name
        limit_conf.remaining_header = "X-AI-RateLimit-Remaining-" .. name
        limit_conf.reset_header = "X-AI-RateLimit-Reset-" .. name
    end

    -- copy the redis fields straight from the policy's schema so no field is missed
    local extra = policy_to_additional_properties[plugin_conf.policy]
    if extra then
        for k in pairs(extra.properties) do
            limit_conf[k] = plugin_conf[k]
        end
    end
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


local function eval_cost_expr(conf, raw)
    local compiled, err = cost_expr_cache(conf, nil, compile_cost_expr, conf.cost_expr)
    if not compiled then
        return nil, "failed to compile cost_expr: " .. err
    end
    local usage = setmetatable({[RAW_KEY] = raw, [PATHS_KEY] = compiled.paths}, usage_mt)
    local ok, result = pcall(compiled.fn, usage)
    if not ok then
        return nil, "failed to evaluate cost_expr: " .. result
    end
    if type(result) ~= "number" then
        return nil, "cost_expr must return a number, got: " .. type(result)
    end
    if result ~= result or result == math_huge or result == -math_huge then
        return nil, "cost_expr returned non-finite value"
    end
    if result < 0 then
        result = 0
    end
    return math_floor(result + 0.5)
end

local function get_token_usage(conf, ctx)
    if conf.limit_strategy == "expression" then
        local raw = ctx.llm_raw_usage
        if not raw then
            return
        end
        local result, err = eval_cost_expr(conf, raw)
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
    if used_tokens == 0 then
        core.log.info("token usage is 0, skip rate limiting")
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
