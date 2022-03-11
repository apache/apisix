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
local core        = require("apisix.core")
local plugin      = require("apisix.plugin")
local ngx         = ngx
local plugin_name = "cors"
local str_find    = core.string.find
local re_gmatch   = ngx.re.gmatch
local re_compile = require("resty.core.regex").re_match_compile
local re_find = ngx.re.find
local ipairs = ipairs
local origins_pattern = [[^(\*|\*\*|null|\w+://[^,]+(,\w+://[^,]+)*)$]]


local lrucache = core.lrucache.new({
    type = "plugin",
})

local metadata_schema = {
    type = "object",
    properties = {
        allow_origins = {
            type = "object",
            additionalProperties = {
                type = "string",
                pattern = origins_pattern
            }
        },
    },
}

local schema = {
    type = "object",
    properties = {
        allow_origins = {
            description =
                "you can use '*' to allow all origins when no credentials," ..
                "'**' to allow forcefully(it will bring some security risks, be carefully)," ..
                "multiple origin use ',' to split. default: *.",
            type = "string",
            pattern = origins_pattern,
            default = "*"
        },
        allow_methods = {
            description =
                "you can use '*' to allow all methods when no credentials," ..
                "'**' to allow forcefully(it will bring some security risks, be carefully)," ..
                "multiple method use ',' to split. default: *.",
            type = "string",
            default = "*"
        },
        allow_headers = {
            description =
                "you can use '*' to allow all header when no credentials," ..
                "'**' to allow forcefully(it will bring some security risks, be carefully)," ..
                "multiple header use ',' to split. default: *.",
            type = "string",
            default = "*"
        },
        expose_headers = {
            description =
                "you can use '*' to expose all header when no credentials," ..
                "'**' to allow forcefully(it will bring some security risks, be carefully)," ..
                "multiple header use ',' to split. default: *.",
            type = "string",
            default = "*"
        },
        max_age = {
            description =
                "maximum number of seconds the results can be cached." ..
                "-1 means no cached, the max value is depend on browser," ..
                "more details plz check MDN. default: 5.",
            type = "integer",
            default = 5
        },
        allow_credential = {
            description =
                "allow client append credential. according to CORS specification," ..
                "if you set this option to 'true', you can not use '*' for other options.",
            type = "boolean",
            default = false
        },
        allow_origins_by_regex = {
            type = "array",
            description =
                "you can use regex to allow specific origins when no credentials," ..
                "for example use [.*\\.test.com] to allow a.test.com and b.test.com",
            items = {
                type = "string",
                minLength = 1,
                maxLength = 4096,
            },
            minItems = 1,
            uniqueItems = true,
        },
        allow_origins_by_metadata = {
            type = "array",
            description =
                "set allowed origins by referencing origins in plugin metadata",
            items = {
                type = "string",
                minLength = 1,
                maxLength = 4096,
            },
            minItems = 1,
            uniqueItems = true,
        },
    }
}

local _M = {
    version = 0.1,
    priority = 4000,
    name = plugin_name,
    schema = schema,
    metadata_schema = metadata_schema,
}


local function create_multiple_origin_cache(allow_origins)
    if not str_find(allow_origins, ",") then
        return nil
    end
    local origin_cache = {}
    local iterator, err = re_gmatch(allow_origins, "([^,]+)", "jiox")
    if not iterator then
        core.log.error("match origins failed: ", err)
        return nil
    end
    while true do
        local origin, err = iterator()
        if err then
            core.log.error("iterate origins failed: ", err)
            return nil
        end
        if not origin then
            break
        end
        origin_cache[origin[0]] = true
    end
    return origin_cache
end


function _M.check_schema(conf, schema_type)
    if schema_type == core.schema.TYPE_METADATA then
        return core.schema.check(metadata_schema, conf)
    end
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end
    if conf.allow_credential then
        if conf.allow_origins == "*" or conf.allow_methods == "*" or
            conf.allow_headers == "*" or conf.expose_headers == "*" then
            return false, "you can not set '*' for other option when 'allow_credential' is true"
        end
    end
    if conf.allow_origins_by_regex then
        for i, re_rule in ipairs(conf.allow_origins_by_regex) do
            local ok, err = re_compile(re_rule, "j")
            if not ok then
                return false, err
            end
        end
    end

    return true
end


local function set_cors_headers(conf, ctx)
    local allow_methods = conf.allow_methods
    if allow_methods == "**" then
        allow_methods = "GET,POST,PUT,DELETE,PATCH,HEAD,OPTIONS,CONNECT,TRACE"
    end

    core.response.set_header("Access-Control-Allow-Origin", ctx.cors_allow_origins)
    if ctx.cors_allow_origins ~= "*" then
        core.response.add_header("Vary", "Origin")
    end

    core.response.set_header("Access-Control-Allow-Methods", allow_methods)
    core.response.set_header("Access-Control-Max-Age", conf.max_age)
    core.response.set_header("Access-Control-Expose-Headers", conf.expose_headers)
    if conf.allow_headers == "**" then
        core.response.set_header("Access-Control-Allow-Headers",
            core.request.header(ctx, "Access-Control-Request-Headers"))
    else
        core.response.set_header("Access-Control-Allow-Headers", conf.allow_headers)
    end
    if conf.allow_credential then
        core.response.set_header("Access-Control-Allow-Credentials", true)
    end
end

local function process_with_allow_origins(allow_origins, ctx, req_origin,
                                          cache_key, cache_version)
    if allow_origins == "**" then
        allow_origins = req_origin or '*'
    end

    local multiple_origin, err
    if cache_key and cache_version then
        multiple_origin, err = lrucache(
                cache_key, cache_version, create_multiple_origin_cache, allow_origins
        )
    else
        multiple_origin, err = core.lrucache.plugin_ctx(
                lrucache, ctx, nil, create_multiple_origin_cache, allow_origins
        )
    end

    if err then
        return 500, {message = "get multiple origin cache failed: " .. err}
    end

    if multiple_origin then
        if multiple_origin[req_origin] then
            allow_origins = req_origin
        else
            return
        end
    end

    return allow_origins
end

local function process_with_allow_origins_by_regex(conf, ctx, req_origin)
    if conf.allow_origins_by_regex == nil then
        return
    end

    if not conf.allow_origins_by_regex_rules_concat then
        local allow_origins_by_regex_rules = {}
        for i, re_rule in ipairs(conf.allow_origins_by_regex) do
            allow_origins_by_regex_rules[i] = re_rule
        end
        conf.allow_origins_by_regex_rules_concat = core.table.concat(
            allow_origins_by_regex_rules, "|")
    end

    -- core.log.warn("regex: ", conf.allow_origins_by_regex_rules_concat, "\n ")
    local matched = re_find(req_origin, conf.allow_origins_by_regex_rules_concat, "jo")
    if matched then
        return req_origin
    end
end


local function match_origins(req_origin, allow_origins)
    return req_origin == allow_origins or allow_origins == '*'
end

local function process_with_allow_origins_by_metadata(allow_origins_by_metadata, ctx, req_origin)
    if allow_origins_by_metadata == nil then
        return
    end

    local metadata = plugin.plugin_metadata(plugin_name)
    if metadata and metadata.value.allow_origins then
        local allow_origins_map = metadata.value.allow_origins
        for _, key in ipairs(allow_origins_by_metadata) do
            local allow_origins_conf = allow_origins_map[key]
            local allow_origins = process_with_allow_origins(allow_origins_conf, ctx, req_origin,
                    plugin_name .. "#" .. key, metadata.modifiedIndex)
            if match_origins(req_origin, allow_origins) then
                return req_origin
            end
        end
    end
end


function _M.rewrite(conf, ctx)
    -- save the original request origin as it may be changed at other phase
    ctx.original_request_origin = core.request.header(ctx, "Origin")
    if ctx.var.request_method == "OPTIONS" then
        return 200
    end
end


function _M.header_filter(conf, ctx)
    local req_origin =  ctx.original_request_origin
    -- Try allow_origins first, if mismatched, try allow_origins_by_regex.
    local allow_origins
    allow_origins = process_with_allow_origins(conf.allow_origins, ctx, req_origin)
    if not match_origins(req_origin, allow_origins) then
        allow_origins = process_with_allow_origins_by_regex(conf, ctx, req_origin)
    end
    if not allow_origins then
        allow_origins = process_with_allow_origins_by_metadata(
                conf.allow_origins_by_metadata, ctx, req_origin
        )
    end
    if allow_origins then
        ctx.cors_allow_origins = allow_origins
        set_cors_headers(conf, ctx)
    end
end

return _M
