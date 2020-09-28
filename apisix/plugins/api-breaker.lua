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
local ngx = ngx
local math = math
local os = os
local ipairs   = ipairs
local core = require("apisix.core")
local plugin_name = "api-breaker"

local shared_buffer = ngx.shared['plugin-'.. plugin_name]

local schema = {
    type = "object",
    properties = {
        response_code = {
            type = "integer",
            minimum = 200,
            maximum = 599,
        },
        unhealthy = {
            type = "object",
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
            },
        },
        healthy = {
            type = "object",
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
    },
    required = {"response_code", "unhealthy", "healthy"},
}

local function is_unhealthy(unhealthy_status, upstream_statu)
    for _, unhealthy in ipairs(unhealthy_status) do
        if unhealthy == upstream_statu then
            return true
        end
    end

    return false
end


local function is_healthy(healthy_status, upstream_statu)
    for _, healthy in ipairs(healthy_status) do
        if healthy == upstream_statu then
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
    priority = 1000,
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
    local unhealthy_val, _ = shared_buffer:get(unhealthy_cache_key(ctx))
    local unhealthy_lastime, _ = shared_buffer:get(unhealthy_lastime_cache_key(ctx))

    if unhealthy_val and unhealthy_lastime then
        local ride = math.ceil(unhealthy_val / conf.unhealthy.failures)
        if ride < 1 then
            ride = 1
        end

        if unhealthy_lastime + 2^ride >= os.time() then
            return conf.response_code
        end
    end
end


function _M.header_filter(conf, ctx)
    local unhealthy_status = conf.unhealthy.http_statuses;
    local healthy_status = conf.healthy.http_statuses;

    local upstream_statu = core.response.get_upstream_status(ctx)

    if is_unhealthy(unhealthy_status, upstream_statu) then
        local newval, _ = shared_buffer:incr(unhealthy_cache_key(ctx), 1, 0, 600)
        shared_buffer:expire(unhealthy_cache_key(ctx), 600)
        shared_buffer:delete(healthy_cache_key(ctx)) -- del healthy numeration

        core.log.info("unhealthy-" .. core.request.get_host(ctx) .. ctx.var.uri, " ", newval)
        if 0 == newval % conf.unhealthy.failures then
            shared_buffer:set(unhealthy_lastime_cache_key(ctx), os.time(), 600)
        end

    elseif is_healthy(healthy_status, upstream_statu) then
        local unhealthy_val, _ = shared_buffer:get(unhealthy_cache_key(ctx))
        if unhealthy_val then
            local healthy_val, _ = shared_buffer:incr(healthy_cache_key(ctx), 1, 0, 600)
            shared_buffer:expire(healthy_cache_key(ctx), 600)

            if healthy_val >= conf.healthy.successes then
                core.log.info(healthy_cache_key(ctx), " ", healthy_val)
                shared_buffer:delete(unhealthy_cache_key(ctx))
                shared_buffer:delete(healthy_cache_key(ctx))
                shared_buffer:delete(unhealthy_lastime_cache_key(ctx))
            end
        end
    end
end

return _M
