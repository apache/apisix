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

--- Define the request context.
--
-- @module core.ctx

local core_str     = require("apisix.core.string")
local core_tab     = require("apisix.core.table")
local request      = require("apisix.core.request")
local log          = require("apisix.core.log")
local json         = require("apisix.core.json")
local config_local = require("apisix.core.config_local")
local tablepool    = require("tablepool")
local get_var      = require("resty.ngxvar").fetch
local get_request  = require("resty.ngxvar").request
local ck           = require "resty.cookie"
local gq_parse     = require("graphql").parse
local setmetatable = setmetatable
local sub_str      = string.sub
local ngx          = ngx
local ngx_var      = ngx.var
local re_gsub      = ngx.re.gsub
local ipairs       = ipairs
local type         = type
local error        = error
local pcall        = pcall


local _M = {version = 0.2}
local GRAPHQL_DEFAULT_MAX_SIZE       = 1048576               -- 1MiB
local GRAPHQL_REQ_DATA_KEY           = "query"
local GRAPHQL_REQ_METHOD_HTTP_GET    = "GET"
local GRAPHQL_REQ_METHOD_HTTP_POST   = "POST"
local GRAPHQL_REQ_MIME_JSON          = "application/json"


local fetch_graphql_data = {
    [GRAPHQL_REQ_METHOD_HTTP_GET] = function(ctx, max_size)
        local body = request.get_uri_args(ctx)[GRAPHQL_REQ_DATA_KEY]
        if not body then
            return nil, "failed to read graphql data, args[" ..
                        GRAPHQL_REQ_DATA_KEY .. "] is nil"
        end

        if type(body) == "table" then
            body = body[1]
        end

        return body
    end,

    [GRAPHQL_REQ_METHOD_HTTP_POST] = function(ctx, max_size)
        local body, err = request.get_body(max_size, ctx)
        if not body then
            return nil, "failed to read graphql data, " .. (err or "request body has zero size")
        end

        if request.header(ctx, "Content-Type") == GRAPHQL_REQ_MIME_JSON then
            local res
            res, err = json.decode(body)
            if not res then
                return nil, "failed to read graphql data, " .. err
            end

            if not res[GRAPHQL_REQ_DATA_KEY] then
                return nil, "failed to read graphql data, json body[" ..
                            GRAPHQL_REQ_DATA_KEY .. "] is nil"
            end

            body = res[GRAPHQL_REQ_DATA_KEY]
        end

        return body
    end
}


local function parse_graphql(ctx)
    local local_conf, err = config_local.local_conf()
    if not local_conf then
        return nil, "failed to get local conf: " .. err
    end

    local max_size = GRAPHQL_DEFAULT_MAX_SIZE
    local size = core_tab.try_read_attr(local_conf, "graphql", "max_size")
    if size then
        max_size = size
    end

    local method = request.get_method()
    local func = fetch_graphql_data[method]
    if not func then
        return nil, "graphql not support `" .. method .. "` request"
    end

    local body
    body, err = func(ctx, max_size)
    if not body then
        return nil, err
    end

    local ok, res = pcall(gq_parse, body)
    if not ok then
        return nil, "failed to parse graphql: " .. res .. " body: " .. body
    end

    if #res.definitions == 0 then
        return nil, "empty graphql: " .. body
    end

    return res
end


local function get_parsed_graphql()
    local ctx = ngx.ctx.api_ctx
    if ctx._graphql then
        return ctx._graphql
    end

    local res, err = parse_graphql(ctx)
    if not res then
        log.error(err)
        ctx._graphql = {}
        return ctx._graphql
    end

    if #res.definitions > 1 then
        log.warn("Multiple operations are not supported.",
                    "Only the first one is handled")
    end

    local def = res.definitions[1]
    local fields = def.selectionSet.selections
    local root_fields = core_tab.new(#fields, 0)
    for i, f in ipairs(fields) do
        root_fields[i] = f.name.value
    end

    local name = ""
    if def.name and def.name.value then
        name = def.name.value
    end

    ctx._graphql = {
        name = name,
        operation = def.operation,
        root_fields = root_fields,
    }

    return ctx._graphql
end


do
    local var_methods = {
        method = ngx.req.get_method,
        cookie = function ()
            if ngx.var.http_cookie then
                return ck:new()
            end
        end
    }

    local no_cacheable_var_names = {
        -- var.args should not be cached as it can be changed via set_uri_args
        args = true,
        is_args = true,
    }

    local ngx_var_names = {
        upstream_scheme            = true,
        upstream_host              = true,
        upstream_upgrade           = true,
        upstream_connection        = true,
        upstream_uri               = true,

        upstream_mirror_uri        = true,

        upstream_cache_zone        = true,
        upstream_cache_zone_info   = true,
        upstream_no_cache          = true,
        upstream_cache_key         = true,
        upstream_cache_bypass      = true,

        var_x_forwarded_proto = true,
        var_x_forwarded_port  = true,
        var_x_forwarded_host  = true,
    }

    -- sort in alphabetical
    local apisix_var_names = {
        balancer_ip = true,
        balancer_port = true,
        consumer_group_id = true,
        consumer_name = true,
        resp_body = function(ctx)
            -- only for logger and requires the logger to have a special configuration
            return ctx.resp_body or ''
        end,
        route_id = true,
        route_name = true,
        service_id = true,
        service_name = true,
    }

    local mt = {
        __index = function(t, key)
            local cached = t._cache[key]
            if cached ~= nil then
                return cached
            end

            if type(key) ~= "string" then
                error("invalid argument, expect string value", 2)
            end

            local val
            local method = var_methods[key]
            if method then
                val = method()

            elseif core_str.has_prefix(key, "cookie_") then
                local cookie = t.cookie
                if cookie then
                    local err
                    val, err = cookie:get(sub_str(key, 8))
                    if err then
                        log.warn("failed to fetch cookie value by key: ",
                                 key, " error: ", err)
                    end
                end

            elseif core_str.has_prefix(key, "arg_") then
                local arg_key = sub_str(key, 5)
                local args = request.get_uri_args()[arg_key]
                if args then
                    if type(args) == "table" then
                        val = args[1]
                    else
                        val = args
                    end
                end

            elseif core_str.has_prefix(key, "post_arg_") then
                -- only match default post form
                if request.header(nil, "Content-Type") == "application/x-www-form-urlencoded" then
                    local arg_key = sub_str(key, 10)
                    local args = request.get_post_args()[arg_key]
                    if args then
                        if type(args) == "table" then
                            val = args[1]
                        else
                            val = args
                        end
                    end
                end

            elseif core_str.has_prefix(key, "http_") then
                key = key:lower()
                key = re_gsub(key, "-", "_", "jo")
                val = get_var(key, t._request)

            elseif core_str.has_prefix(key, "graphql_") then
                -- trim the "graphql_" prefix
                key = sub_str(key, 9)
                val = get_parsed_graphql()[key]

            else
                local getter = apisix_var_names[key]
                if getter then
                    local ctx = t._ctx
                    if getter == true then
                        val = ctx and ctx[key]
                    else
                        -- the getter is registered by ctx.register_var
                        val = getter(ctx)
                    end

                else
                    val = get_var(key, t._request)
                end
            end

            if val ~= nil and not no_cacheable_var_names[key] then
                t._cache[key] = val
            end

            return val
        end,

        __newindex = function(t, key, val)
            if ngx_var_names[key] then
                ngx_var[key] = val
            end

            -- log.info("key: ", key, " new val: ", val)
            t._cache[key] = val
        end,
    }

---
-- Register custom variables.
-- Register variables globally, and use them as normal builtin variables.
-- Note that the custom variables can't be used in features that depend
-- on the Nginx directive, like `access_log_format`.
--
-- @function core.ctx.register_var
-- @tparam string name custom variable name
-- @tparam function getter The fetch function for custom variables.
-- @tparam table opts An optional options table which controls the behavior about the variable
-- @usage
-- local core = require "apisix.core"
--
-- core.ctx.register_var("a6_labels_zone", function(ctx)
--     local route = ctx.matched_route and ctx.matched_route.value
--     if route and route.labels then
--         return route.labels.zone
--     end
--     return nil
-- end)
--
-- We support the options below in the `opts`:
-- * no_cacheable: if the result of getter is cacheable or not. Default to `false`.
function _M.register_var(name, getter, opts)
    if type(getter) ~= "function" then
        error("the getter of registered var should be a function")
    end

    apisix_var_names[name] = getter

    if opts then
        if opts.no_cacheable then
            no_cacheable_var_names[name] = true
        end
    end
end

function _M.set_vars_meta(ctx)
    local var = tablepool.fetch("ctx_var", 0, 32)
    if not var._cache then
        var._cache = {}
    end

    var._request = get_request()
    var._ctx = ctx
    setmetatable(var, mt)
    ctx.var = var
end

function _M.release_vars(ctx)
    if ctx.var == nil then
        return
    end

    core_tab.clear(ctx.var._cache)
    tablepool.release("ctx_var", ctx.var, true)
    ctx.var = nil
end

end -- do


return _M
