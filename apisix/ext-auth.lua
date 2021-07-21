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
local http = require("resty.http")
local ck = require("resty.cookie")
local ngx = ngx
local ipairs = ipairs
local type = type
local rawget = rawget
local rawset = rawset
local setmetatable = setmetatable
local string = string

local plugin_name = "ext-auth"
local ext_lrucache = core.lrucache.new({
    ttl = 60, count = 1024
})

local schema = {
    type = "object",
    properties = {
        ext_auth_url = {
            type = "string",
            minLength = 1,
            maxLength = 4096
        },
        ext_auth_method = {
            type = "string",
            default = "GET",
            enum = { "GET", "POST" },
        },
        ext_headers = {
            type = "array",
            items = {
                type = "string",
                minLength = 1,
                maxLength = 100
            },
            uniqueItems = true
        },
        ext_args = {
            type = "array",
            items = {
                type = "string",
                minLength = 1,
                maxLength = 100
            },
            uniqueItems = true
        },
        ext_keepalive = {
            type = "boolean",
            default = true
        },
        ext_keepalive_timeout = {
            type = "integer",
            minimum = 1000,
            default = 60000
        },
        ext_keepalive_pool = {
            type = "integer",
            minimum = 1,
            default = 5
        },
        check_termination = {
            type = "boolean",
            default = true
        },
    },
    required = { "ext_auth_url" },
}

local _M = {
    version = 0.1,
    priority = 1555,
    name = plugin_name,
    schema = schema,
}

function _M.check_schema(conf)

    return core.schema.check(schema, conf)

end

local function get_auth_token(ctx)

    local token = ctx.var.http_x_auth_token
    if token then
        return token
    end

    token = ctx.var.http_authorization
    if token then
        return token
    end

    token = ctx.var.arg_auth_token
    if token then
        return token
    end

    local cookie, err = ck:new()
    if not cookie or err then
        return nil
    end

    local val, error = cookie:get("auth-token")
    if error then
        return nil
    end
    return val

end

local function fail_response(message, init_values)

    local response = init_values or {}
    response.message = message
    return response

end

local function new_table()
    local t = {}
    local lt = {}
    local _mt = {
        __index = function(t, k)
            return rawget(lt, string.lower(k))
        end,
        __newindex = function(t, k, v)
            rawset(t, k, v)
            rawset(lt, string.lower(k), v)
        end,
    }
    return setmetatable(t, _mt)
end

--proxy headers
local function request_headers(config, ctx)
    local req_headers = new_table()
    local headers = core.request.headers(ctx)
    local ext_headers = config.ext_headers
    if not ext_headers then
        return req_headers
    end
    for i, field in ipairs(ext_headers) do
        local v = headers[field]
        if v then
            req_headers[field] = v
        end
    end
    return req_headers
end



--proxy args
local function get_ext_args(ext_args)
    local req_args = new_table()
    if not ext_args then
        return req_args
    end
    local args = ngx.req.get_uri_args()
    for i, field in ipairs(ext_args) do
        local v = args[field]
        if v then
            req_args[field] = v
        end
    end
    return req_args
end

-- Configure request parameters.
local function ext_configure_params(args, config, ext_headers)
    ext_headers["Content-Type"] = "application/json; charset=utf-8"
    local ext_auth_params = {
        ssl_verify = false,
        method = config.ext_auth_method,
        headers = ext_headers,
    }
    if config.ext_keepalive then
        ext_auth_params.keepalive_timeout = config.ext_keepalive_timeout
        ext_auth_params.keepalive_pool = config.ext_keepalive_pool
    else
        ext_auth_params.keepalive = config.ext_keepalive
    end
    local url = config.ext_auth_url .. "?" .. ngx.encode_args(args)
    return ext_auth_params, url

end

-- timeout in ms
local function http_req(url, ext_auth_params)
    local httpc = http.new()
    httpc:set_timeout(1000 * 10)
    local res, err = httpc:request_uri(url, ext_auth_params)
    if err then
        core.log.error("FAIL REQUEST [ ", core.json.encode(ext_auth_params),
                " ] failed! res is nil, err:", err)
        return nil, err
    end
    return res
end

local function get_auth_info(config, ctx, action, path, client_ip, auth_token)
    local ext_headers = request_headers(config, ctx)
    ext_headers["X-Client-Ip"] = client_ip
    ext_headers["Authorization"] = auth_token
    local args = get_ext_args(config.ext_args)
    args['ext_path'] = path
    args['ext_action'] = action
    args['ext_client_ip'] = client_ip
    core.response.set_header("APISIX-Ext-Cache", 'no-cache')
    local ext_auth_params, url = ext_configure_params(args, config, ext_headers)
    local res, err = http_req(url, ext_auth_params)
    return { res = res, err = err }
end

function _M.rewrite(conf, ctx)
    local config = conf
    local url = ctx.var.uri
    local action = ctx.var.request_method
    local client_ip = ctx.var.http_x_real_ip or core.request.get_ip(ctx)
    local auth_token = get_auth_token(ctx)

    if auth_token then
        local res, ext_data
        if config.ext_cache then
            core.response.set_header("APISIX-Ext-Cache", 'cache')
            res = ext_lrucache(plugin_name .. "#" .. auth_token, config.version,
                    get_auth_info, config, ctx, action, url, client_ip, auth_token)
        else
            res = get_auth_info(config, ctx, action, url, client_ip, auth_token)
        end

        local ext_res = res.res
        if res.err then
            core.response.set_header("Content-Type", "application/json; charset=utf-8")
            return 500, fail_response(res.err, { status_code = 500 })
        end

        if ext_res.status ~= 200 and config.check_termination then
            core.response.set_header("Content-Type", "application/json; charset=utf-8")
            return ext_res.status, fail_response('ext-auth check permission failed',
                    { status_code = ext_res.status })
        end

        local ext_body, err = core.json.decode(ext_res.body)
        if not ext_body and config.check_termination then
            core.response.set_header("Content-Type", "application/json; charset=utf-8")
            return 500, fail_response("JSON decoding failed: " .. err,
                    { status_code = 500 })
        end

    elseif config.check_termination then
         core.response.set_header("Content-Type", "application/json; charset=utf-8")
         return 401, fail_response("Missing auth token in request",
                    { status_code = 401 })
    end
    core.log.info("ext-auth check permission passed")
end

return _M