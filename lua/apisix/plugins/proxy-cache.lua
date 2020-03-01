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
local tab_insert = table.insert
local tab_concat = table.concat
local re_gmatch = ngx.re.gmatch
local sub_str = string.sub
local ngx = ngx
local ipairs = ipairs

local lrucache = core.lrucache.new({
    ttl = 300, count = 100
})

local plugin_name = "proxy-cache"

local schema = {
    type = "object",
    properties = {
        cache_zone = {
            type = "string",
            minLength = 1
        },
        cache_key = {
            type = "array",
            minItems = 1,
            items = {
                description = "a key for caching",
                type = "string",
                pattern = [[(^[^\$].+$|^\$[0-9a-zA-Z_]+$)]]
            },
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
                description = "http method",
                type = "string",
                enum = {"GET", "POST", "PUT", "DELETE", "PATCH", "HEAD",
                    "OPTIONS", "CONNECT", "TRACE"},
            },
            uniqueItems = true,
            default = {"GET", "HEAD"},
        },
        hide_cache_headers = {
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
    },
    required = {"cache_zone", "cache_key"},
}

local _M = {
    version = 0.1,
    priority = 1009,
    name = plugin_name,
    schema = schema,
}


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    return true
end


local tmp = {}
local function generate_complex_value(data, ctx)
    core.table.clear(tmp)

    core.log.info("proxy-cache complex value: ", core.json.delay_encode(data))
    for i, value in ipairs(data) do
        core.log.info("proxy-cache complex value index-", i, ": ", value)

        if sub_str(value, 1, 1) == "$" then
            tab_insert(tmp, ctx.var[sub_str(value, 2)])
        else
            tab_insert(tmp, value)
        end
    end

    return tab_concat(tmp, "")
end


function _M.rewrite(conf, ctx)
    core.log.info("proxy-cache plugin rewrite phase, conf: ", core.json.delay_encode(conf))

    ctx.var.upstream_cache_zone = conf.cache_zone

    local value, err = generate_complex_value(conf.cache_key, ctx)
    if not value then
        core.log.error("failed to generate the complex value by: ", conf.cache_key, " error: ", err)
        core.response.exit(500)
    end

    ctx.var.upstream_cache_key = value
    core.log.info("proxy-cache cache key value:", value)

    local value, err = generate_complex_value(conf.cache_bypass, ctx)
    if not value then
        core.log.error("failed to generate the complex value by: ",
                       conf.cache_bypass, " error: ", err)
        core.response.exit(500)
    end

    ctx.var.upstream_cache_bypass = value
    core.log.info("proxy-cache cache bypass value:", value)
end


-- check whether the request method and response status
-- match the user defined.
function match_method_and_status(conf, ctx)
    local match_method, match_status = false, false

    -- Maybe there is no need for optimization here.
    for _, method in ipairs(conf.cache_method) do
        if method == ctx.var.request_method then
            match_method = true
            break
        end
    end

    for _, status in ipairs(conf.cache_http_status) do
        if status == ngx.status then
            match_status = true
            break
        end
    end

    if match_method and match_status then
        return true
    end

    return false
end


function _M.header_filter(conf, ctx)
    core.log.info("proxy-cache plugin header filter phase, conf: ", core.json.delay_encode(conf))

    local no_cache = "1"

    if match_method_and_status(conf, ctx) then
        no_cache = "0"
    end

    local value, err = generate_complex_value(conf.no_cache, ctx)
    if not value then
        core.log.error("failed to generate the complex value by: ", conf.no_cache, " error: ", err)
        core.response.exit(500)
    end

    core.log.info("proxy-cache no-cache value:", value)

    if value ~= nil and value ~= "" and value ~= "0" then
        no_cache = "1"
    end

    if conf.hide_cache_headers == true then
        ctx.var.upstream_hdr_cache_control = ""
        ctx.var.upstream_hdr_expires = ""
    else
        ctx.var.upstream_hdr_cache_control = ctx.var.upstream_http_cache_control
        ctx.var.upstream_hdr_expires = ctx.var.upstream_http_expires
    end

    ctx.var.upstream_no_cache = no_cache
    core.log.info("proxy-cache no cache:", no_cache)
end


return _M
