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
local resty_sha256 = require("resty.sha256")
local ck = require("resty.cookie")
local ngx = ngx
local plugin_name = "csrf"
local ngx_encode_base64 = ngx.encode_base64
local ngx_decode_base64 = ngx.decode_base64
local ngx_time = ngx.time
local cookie_time = ngx.cookie_time
local math = math

local schema = {
    type = "object",
    properties = {
        key = {
            description = "use to generate csrf token",
            type = "string",
        },
        expires = {
            description = "expires time(s) for csrf token",
            type = "integer",
            default = 7200
        },
        name = {
            description = "the csrf token name",
            type = "string",
            default = "apisix_csrf_token"
        }
    },
    required = {"key"}
}

local _M = {
    version = 0.1,
    priority = 2980,
    name = plugin_name,
    schema = schema,
}

function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end


local function gen_sign(random, expires, key)
    local sha256 = resty_sha256:new()

    local sign = {
        random = random,
        expires = expires,
        key = key,
    }

    sha256:update(core.json.encode(sign))
    local digest = sha256:final()

    return ngx_encode_base64(digest)
end


local function gen_csrf_token(conf)
    local random = math.random()
    local sign = gen_sign(random, conf.expires, conf.key)

    local token = {
        random = random,
        expires = conf.expires,
        sign = sign,
    }

    local cookie = ngx_encode_base64(core.json.encode(token))
    return cookie
end


local function check_csrf_token(conf, ctx, token)
    local _token = ngx_decode_base64(token)
    if _token == nil then
        core.log.error("csrf token is null")
        return false
    end

    local _token_table, err = core.json.decode(_token)
    if err then
        core.log.error("decode token error: ", err)
        return false
    end

    local random = _token_table["random"]
    if not random then
        core.log.error("no random in token")
        return false
    end

    local expires = _token_table["expires"]
    if not expires then
        core.log.error("no expires in token")
        return false
    end

    local sign = gen_sign(random, expires, conf.key)
    if _token_table["sign"] ~= sign then
        return false
    end

    return true
end


function _M.access(conf, ctx)
    local method = core.request.get_method(ctx)
    if method == 'GET' then
        return
    end

    local token = core.request.header(ctx, conf.name)
    if not token then
        return 401, {error_msg = "no csrf token in headers"}
    end

    local cookie, err = ck:new()
    if not cookie then
        return nil, err
    end

    local field_cookie, err = cookie:get(conf.name)
    if not field_cookie then
        return 401, {error_msg = "no csrf cookie"}
    end

    if err then
        core.log.error(err)
        return 400, {error_msg = "read csrf cookie failed"}
    end

    if token ~= field_cookie then
        return 401, {error_msg = "csrf token mismatch"}
    end

    local result = check_csrf_token(conf, ctx, token)
    if not result then
        return 401, {error_msg = "Failed to verify the csrf token signature"}
    end
end


function _M.header_filter(conf, ctx)
    local csrf_token = gen_csrf_token(conf)
    core.response.add_header("Set-Cookie", {conf.name .. "=" .. csrf_token
                                            .. ";path=/;Expires="
                                            .. cookie_time(ngx_time() + conf.expires)})
end

return _M
