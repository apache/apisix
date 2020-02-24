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
local ngx = ngx
local ipairs = ipairs
local tostring = tostring

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
            type = "string",
            minLength = 1
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
                default = {"GET", "HEAD"},
            },
            uniqueItems = true,
            default = {"GET", "HEAD"},
        },
        hide_cache_headers = {
            type = "boolean",
            default = false,
        },
        cache_strategy = {
            type = "string",
            default = "disk",
            enum = {"disk", "memory"},
            minLength = 0
        },
        cache_bypass = {
            type = "string",
            default = "1",
            minLength = 0
        },
        no_cache = {
            type = "string",
            default = "0",
            minLength = 0
        },
    },
    required = {"cache_zone", "cache_key"},
}

local _M = {
    version = 0.1,
    priority = 1007,
    name = plugin_name,
    schema = schema,
}

function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    if conf.cache_strategy == "memory" then
        return false, "memory cache is not yet supported."
    end

    local t = {}
    for _, method in ipairs(conf.cache_method) do
        t[method] = "true"
    end

    conf.cache_method = t

    local t = {}
    for _, status in ipairs(conf.cache_http_status) do
        t[tostring(status)] = "true"
    end

    conf.cache_http_status = t

    return true
end

-- Copy from redirect plugin, this function is useful.
-- It can be extracted as a public function.
local function parse_complex_value(complex_value)

    local reg = [[ (\\\$[0-9a-zA-Z_]+) | ]]     -- \$host
            .. [[ \$\{([0-9a-zA-Z_]+)\} | ]]    -- ${host}
            .. [[ \$([0-9a-zA-Z_]+) | ]]        -- $host
            .. [[ (\$|[^$\\]+) ]]               -- $ or others
    local iterator, err = re_gmatch(complex_value, reg, "jiox")
    if not iterator then
        return nil, err
    end

    local t = {}
    while true do
        local m, err = iterator()
        if err then
            return nil, err
        end

        if not m then
            break
        end

        tab_insert(t, m)
    end

    return t
end


local tmp = {}
local function generate_complex_value(data, ctx)
    local segs_value, err = lrucache(data, nil, parse_complex_value, data)
    if not segs_value then
        return nil, err
    end

    core.table.clear(tmp)

    for i, value in ipairs(segs_value) do
        core.log.info("complex value(", data, ") seg-", i, ": ", core.json.delay_encode(value))

        local pat1 = value[1]    -- \$host
        local pat2 = value[2]    -- ${host}
        local pat3 = value[3]    -- $host
        local pat4 = value[4]    -- $ or others

        if pat2 or pat3 then
            tab_insert(tmp, ctx.var[pat2 or pat3])
        else
            tab_insert(tmp, pat1 or pat4)
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


function _M.header_filter(conf, ctx)
    core.log.info("proxy-cache plugin header filter phase, conf: ", core.json.delay_encode(conf))

    local no_cache = "1"

    if conf.cache_method[ctx.var.request_method] then
        no_cache = "0"
    end

    if conf.cache_http_status[tostring(ngx.status)] then
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
