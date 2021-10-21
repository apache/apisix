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

local memory_handler = require("apisix.plugins.proxy-cache.memory_handler")
local disk_handler = require("apisix.plugins.proxy-cache.disk_handler")
local util = require("apisix.plugins.proxy-cache.util")
local core = require("apisix.core")
local ipairs = ipairs

local plugin_name = "proxy-cache"

local STRATEGY_DISK = "disk"
local STRATEGY_MEMORY = "memory"

local schema = {
    type = "object",
    properties = {
        cache_zone = {
            type = "string",
            minLength = 1,
            maxLength = 100,
            default = "disk_cache_one",
        },
        cache_strategy = {
            type = "string",
            enum = {STRATEGY_DISK, STRATEGY_MEMORY},
            default = STRATEGY_DISK,
        },
        cache_key = {
            type = "array",
            minItems = 1,
            items = {
                description = "a key for caching",
                type = "string",
                pattern = [[(^[^\$].+$|^\$[0-9a-zA-Z_]+$)]],
            },
            default = {"$host", "$request_uri"}
        },
        cache_http_status = {
            type = "array",
            minItems = 1,
            items = {
                description = "http response status",
                type = "integer",
                minimum = 200,
                maximum = 599,
            },
            uniqueItems = true,
            default = {200, 301, 404},
        },
        cache_method = {
            type = "array",
            minItems = 1,
            items = {
                description = "supported http method",
                type = "string",
                enum = {"GET", "POST", "HEAD"},
            },
            uniqueItems = true,
            default = {"GET", "HEAD"},
        },
        hide_cache_headers = {
            type = "boolean",
            default = false,
        },
        cache_control = {
            type = "boolean",
            default = false,
        },
        cache_bypass = {
            type = "array",
            minItems = 1,
            items = {
                type = "string",
                pattern = [[(^[^\$].+$|^\$[0-9a-zA-Z_]+$)]]
            },
        },
        no_cache = {
            type = "array",
            minItems = 1,
            items = {
                type = "string",
                pattern = [[(^[^\$].+$|^\$[0-9a-zA-Z_]+$)]]
            },
        },
        cache_ttl = {
            type = "integer",
            minimum = 1,
            default = 300,
        },
    },
}


local _M = {
    version = 0.2,
    priority = 1009,
    name = plugin_name,
    schema = schema,
}


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    for _, key in ipairs(conf.cache_key) do
        if key == "$request_method" then
            return false, "cache_key variable " .. key .. " unsupported"
        end
    end

    local found = false
    local local_conf = core.config.local_conf()
    if local_conf.apisix.proxy_cache then
        for _, cache in ipairs(local_conf.apisix.proxy_cache.zones) do
            if cache.name == conf.cache_zone then
                found = true
            end
        end

        if found == false then
            return false, "cache_zone " .. conf.cache_zone .. " not found"
        end
    end

    return true
end


function _M.access(conf, ctx)
    core.log.info("proxy-cache plugin access phase, conf: ", core.json.delay_encode(conf))

    local value = util.generate_complex_value(conf.cache_key, ctx)
    ctx.var.upstream_cache_key = value
    core.log.info("proxy-cache cache key value:", value)

    local handler
    if conf.cache_strategy == STRATEGY_MEMORY then
        handler = memory_handler
    else
        handler = disk_handler
    end

    return handler.access(conf, ctx)
end


function _M.header_filter(conf, ctx)
    core.log.info("proxy-cache plugin header filter phase, conf: ", core.json.delay_encode(conf))

    local handler
    if conf.cache_strategy == STRATEGY_MEMORY then
        handler = memory_handler
    else
        handler = disk_handler
    end

    handler.header_filter(conf, ctx)
end


function _M.body_filter(conf, ctx)
    core.log.info("proxy-cache plugin body filter phase, conf: ", core.json.delay_encode(conf))

    if conf.cache_strategy == STRATEGY_MEMORY then
        memory_handler.body_filter(conf, ctx)
    end
end


return _M
