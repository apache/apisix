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
local ipairs = ipairs
local error = error
local core = require("apisix.core")

local DEFAULT_EXPTIME = 300 -- TODO: user can config

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
                    default = 1,
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
                    default = 1,
                }
            }
        }
    },
    required = {"unhealthy_response_code", "unhealthy", "healthy"},
}


local function is_unhealthy(unhealthy_status, upstream_status)
    for _, unhealthy in ipairs(unhealthy_status) do
        if unhealthy == upstream_status then
            return true
        end
    end

    return false
end


local function is_healthy(healthy_status, upstream_status)
    for _, healthy in ipairs(healthy_status) do
        if healthy == upstream_status then
            return true
        end
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
    local unhealthy_val, err = shared_buffer:get(unhealthy_cache_key(ctx))
    if err then
        core.log.warn("failed to get unhealthy_cache_key in ngx.shared:", err)
    end

    local unhealthy_lastime, err = shared_buffer:get(unhealthy_lastime_cache_key(ctx))
    if err then
        core.log.warn("failed to get unhealthy_lastime_cache_key in ngx.shared: ", err)
    end

    if unhealthy_val and unhealthy_lastime then
        local ride = math.ceil(unhealthy_val / conf.unhealthy.failures)
        if ride < 1 then
            ride = 1
        end

        -- The maximum intercept request is 5 minutes(DEFAULT_EXPTIME),
        -- and then the upstream service will be retry.
        if unhealthy_lastime + 2^ride >= ngx.time() then
            return conf.unhealthy_response_code
        end
    end
end


function _M.log(conf, ctx)
    local unhealthy_status = conf.unhealthy.http_statuses
    local healthy_status = conf.healthy.http_statuses

    local unhealthy_key = unhealthy_cache_key(ctx)
    local healthy_key = healthy_cache_key(ctx)

    local upstream_status = core.response.get_upstream_status(ctx)

    if is_unhealthy(unhealthy_status, upstream_status) then
        local newval, err = shared_buffer:incr(unhealthy_key, 1, 0, DEFAULT_EXPTIME)
        if err then
            core.log.warn("failed to incr unhealthy_key in ngx.shared: ", err)
        end
        shared_buffer:expire(unhealthy_key, DEFAULT_EXPTIME)
        shared_buffer:delete(healthy_key) -- del healthy numeration

        if 0 == newval % conf.unhealthy.failures then
            shared_buffer:set(unhealthy_lastime_cache_key(ctx), ngx.time(), DEFAULT_EXPTIME)
            core.log.info(unhealthy_key, " ", newval) -- stat change
        end

        return
    end

    if is_healthy(healthy_status, upstream_status) then
        local unhealthy_val, err = shared_buffer:get(unhealthy_key)
        if err then
            core.log.warn("failed to get unhealthy_key in ngx.shared: ", err)
        end

        if unhealthy_val then
            local healthy_val, err = shared_buffer:incr(healthy_key, 1, 0, DEFAULT_EXPTIME)
            if err then
                core.log.warn("failed to incr healthy_key in ngx.shared: ", err)
            end
            shared_buffer:expire(healthy_key, DEFAULT_EXPTIME)

            if healthy_val >= conf.healthy.successes then
                core.log.info(healthy_key, " ", healthy_val) -- stat change
                shared_buffer:delete(unhealthy_key)
                shared_buffer:delete(healthy_key)
                shared_buffer:delete(unhealthy_lastime_cache_key(ctx))
            end
        end

        return
    end

    return
end


return _M
