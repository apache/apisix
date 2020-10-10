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
local plugin_name = "api-breaker"
local ngx = ngx
local math = math
local error = error
local core = require("apisix.core")

local shared_buffer = ngx.shared['plugin-'.. plugin_name]
if not shared_buffer then
    error("failed to get ngx.shared dict when load plugin " .. plugin_name)
end


local schema = {
    type = "object",
    properties = {
        unhealthy_response_code = {
            type = "integer",
            minimum = 200,
            maximum = 599,
        },
        max_breaker_seconds = {
            type = "integer",
            minimum = 3,
            default = 300,
        },
        unhealthy = {
            type = "object",
            properties = {
                http_statuses = {
                    type = "array",
                    minItems = 1,
                    items = {
                        type = "integer",
                        minimum = 500,
                        maximum = 599,
                    },
                    uniqueItems = true,
                    default = {500}
                },
                failures = {
                    type = "integer",
                    minimum = 1,
                    default = 3,
                }
            }
        },
        healthy = {
            type = "object",
            properties = {
                http_statuses = {
                    type = "array",
                    minItems = 1,
                    items = {
                        type = "integer",
                        minimum = 200,
                        maximum = 499,
                    },
                    uniqueItems = true,
                    default = {200, 206}
                },
                successes = {
                    type = "integer",
                    minimum = 1,
                    default = 3,
                }
            }
        }
    },
    required = {"unhealthy_response_code", "unhealthy", "healthy"},
}


-- todo: we can move this into `core.talbe`
local function array_index(array, value)
    for i, v in ipairs(array) do
        if v == value then
            return i
        end
    end

    return -1
end


local function is_unhealthy(unhealthy_status, upstream_status)
    local idx = array_index(unhealthy_status, upstream_status);
    if idx > 0 then
        return true
    end

    return false
end


local function is_healthy(healthy_status, upstream_status)
    local idx = array_index(healthy_status, upstream_status);
    if idx > 0 then
        return true
    end

    return false
end


local function healthy_cache_key(ctx)
    return "healthy-" .. core.request.get_host(ctx) .. ctx.var.uri
end


local function unhealthy_cache_key(ctx)
    return "unhealthy-" .. core.request.get_host(ctx) .. ctx.var.uri
end


local function unhealthy_lastime_cache_key(ctx)
    return "unhealthy-lastime" .. core.request.get_host(ctx) .. ctx.var.uri
end


local _M = {
    version = 0.1,
    name = plugin_name,
    priority = 1005,
    schema = schema,
}


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    return true
end


function _M.access(conf, ctx)
    -- unhealthy counts
    local unhealthy_val, err = shared_buffer:get(unhealthy_cache_key(ctx))
    if err then
        core.log.warn("failed to get unhealthy_cache_key in ngx.shared: ", 
                      unhealthy_cache_key(ctx), err)
    end

    -- Timestamp of the last time a unhealthy state was triggered
    local unhealthy_lastime, err = shared_buffer:get(unhealthy_lastime_cache_key(ctx))
    if err then
        core.log.warn("failed to get unhealthy_lastime_cache_key in ngx.shared: ", 
                      unhealthy_lastime_cache_key(ctx), err)
    end

    if unhealthy_val and unhealthy_lastime then
        local multiplication = math.ceil(unhealthy_val / conf.unhealthy.failures)
        if multiplication < 1 then
            multiplication = 1
        end

        -- Cannot exceed the maximum value of the user configuration
        local breaker_time = 2^multiplication
        if breaker_time > conf.max_breaker_seconds then
            breaker_time = conf.max_breaker_seconds
        end

        -- breaker
        if unhealthy_lastime + breaker_time >= ngx.time() then
            return conf.unhealthy_response_code
        end
    end

    return
end


function _M.log(conf, ctx)
    local unhealthy_status = conf.unhealthy.http_statuses
    local healthy_status = conf.healthy.http_statuses

    local unhealthy_key = unhealthy_cache_key(ctx)
    local healthy_key = healthy_cache_key(ctx)

    local upstream_status = core.response.get_upstream_status(ctx)

    if is_unhealthy(unhealthy_status, upstream_status) then
        -- Incremental unhealthy counts
        local newval, err = shared_buffer:incr(unhealthy_key, 1, 0)
        if err then
            core.log.warn("failed to incr unhealthy_key in ngx.shared: ", unhealthy_key, err)
        end
        shared_buffer:delete(healthy_key) -- del healthy numeration

        -- Whether the user-configured number of failures has been reached,
        -- and if so, the timestamp for entering the unhealthy state.
        if 0 == newval % conf.unhealthy.failures then
            shared_buffer:set(unhealthy_lastime_cache_key(ctx), ngx.time(), 
                              conf.max_breaker_seconds)
            core.log.info(unhealthy_key, " ", newval) -- stat change to unhealthy
        end

        return
    end


    if is_healthy(healthy_status, upstream_status) then
        -- Blow operation is only required if it is unhealthy.
        -- the current value of the unhealthy state is taken first.
        local unhealthy_val, err = shared_buffer:get(unhealthy_key)
        if err then
            core.log.warn("failed to get unhealthy_key in ngx.shared: ", unhealthy_key, err)
        end

        if unhealthy_val then
            -- Incremental healthy counts
            local healthy_val, err = shared_buffer:incr(healthy_key, 1, 0)
            if err then
                core.log.warn("failed to incr healthy_key in ngx.shared: ", err)
            end

            -- Continuous Response Normal, stat change to normal.
            -- Clear related status records
            if healthy_val >= conf.healthy.successes then
                core.log.info(healthy_key, " ", healthy_val) -- stat change to normal
                shared_buffer:delete(unhealthy_lastime_cache_key(ctx))
                shared_buffer:delete(unhealthy_key)
                shared_buffer:delete(healthy_key)
            end
        end

        return
    end

    return
end


return _M
