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
local core   = require("apisix.core")
local expr   = require("resty.expr.v1")
local ngx    = ngx
local ngx_now = ngx.now
local ngx_worker_id = ngx.worker.id
local ngx_sleep = ngx.sleep
local ngx_timer_at = ngx.timer.at
local ipairs = ipairs
local tab_concat = table.concat
local tostring = tostring

local lrucache = core.lrucache.new({
    type = "plugin",
})

local math_random = math.random

local plugin_name   = "error-log-collect"

local schema = {
    type = "object",
    properties = {
        vars = {
            type = "array",
            description = "an array of variables expressions;"
                            .. " logs are collected only when all expressions evaluate to true",
        },
        sample_ratio = {
            type = "number",
            minimum = 0.00001,
            maximum = 1,
            default = 1,
            description = "the probability of collecting logs for a request;"
                            .. " 1 means all logs are collected",
        },
        buffer_max_size = {
            type = "integer",
            minimum = 1,
            description = "log buffer capacity; when the number of logs exceeds this value,"
                            .. " the oldest logs will be overwritten",
            default = 1000,
        },
    },
}

local _M = {
    version = 0.1,
    priority = 12100000,
    name = plugin_name,
    schema = schema,
}

function _M.check_schema(conf)
    if conf.vars then
        local ok, err = expr.new(conf.vars)
        if not ok then
            return nil, "failed to validate the 'vars' expression: " .. err
        end
    end
    return core.schema.check(schema, conf)
end


local function collect(conf, ctx)
    local log_buffer = core.log.get_buffer()
    if not log_buffer then
        return
    end

    local elements = log_buffer:drain()
    if #elements == 0 then
        return
    end
    core.log.reset_buffer(conf.buffer_max_size)

    ngx_timer_at(0, function()
        local time = tostring(ngx_now() * 1000)
        local worker_id = tostring(ngx_worker_id()) or ""
        local prefix =  time .. "#" .. worker_id .. " [error-log-collect] "
        core.log.info(prefix, "collecting ", #elements)
        for idx, log_entry in ipairs(elements) do
            if idx % 20 == 0 then
                ngx_sleep(0)
            end
            core.log.error(prefix, tab_concat(log_entry))
        end
    end)
end


function _M.rewrite(conf, ctx)
    if conf.sample_ratio ~= 1 then
        local val = math_random()
        if val >= conf.sample_ratio then
            return
        end
    end
    ngx.ctx.error_log_collecting = true
end


function _M.log(conf, ctx)
    local matched = true
    if conf.vars then
        local e, err = core.lrucache.plugin_ctx(lrucache, ctx, nil, expr.new, conf.vars)
        if not e then
            core.log.error("failed to create expression: ", err)
            return
        end
        matched = e:eval(ctx.var)
    end
    if matched then
        collect(conf, ctx)
    end
end


return _M
