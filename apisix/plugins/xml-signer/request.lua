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
local runtime_ok, apisix_ngx_client = pcall(require, "resty.apisix.client")

local ipairs = ipairs
local ngx = ngx
local tonumber = tonumber
local tostring = tostring
local type = type

local _M = {}

local BODY_DIGEST_HEADERS = {
    "Content-MD5",
    "Digest",
    "Content-Digest",
    "Repr-Digest",
}

local SIZE_UNITS = {
    [""] = 1,
    k = 1024,
    m = 1024 * 1024,
    g = 1024 * 1024 * 1024,
}

local global_body_limit


-- Parse an NGINX size value such as 0, "8192", "512k" or "1m".
local function parse_nginx_size(value)
    if type(value) == "number" then
        return value
    end
    if type(value) ~= "string" then
        return nil
    end
    local number, unit = value:match("^%s*(%d+)%s*([kKmMgG]?)%s*$")
    if not number then
        return nil
    end
    return tonumber(number) * SIZE_UNITS[unit:lower()]
end


-- The operator-configured `nginx_config.http.client_max_body_size`.
-- `set_client_max_body_size` overrides it for the current request, so the
-- Plugin must not raise the limit above what the operator configured.
local function get_global_body_limit()
    if global_body_limit == nil then
        local local_conf = core.config.local_conf()
        local http_conf = local_conf and local_conf.nginx_config
                          and local_conf.nginx_config.http
        global_body_limit = http_conf
                            and parse_nginx_size(http_conf.client_max_body_size)
                            or 0
    end
    return global_body_limit
end


local function effective_body_limit(ctx, configured)
    local limit = configured
    -- client-control sets a Route-specific limit that takes precedence over
    -- the global one.
    local outer_limit = ctx and ctx.client_max_body_size
    if outer_limit == nil then
        outer_limit = get_global_body_limit()
    end
    if outer_limit and outer_limit > 0 and outer_limit < limit then
        limit = outer_limit
    end
    return limit
end


local function contains(values, expected)
    for _, value in ipairs(values) do
        if value == expected then
            return true
        end
    end
    return false
end


local function normalized_content_type(value)
    if not value then
        return ""
    end
    local normalized = value:match("^%s*([^;]+)")
    return normalized and normalized:gsub("%s+$", ""):lower() or ""
end


local function has_unsupported_charset(value)
    if not value then
        return false, nil
    end

    local parameter_start
    local quoted = false
    local escaped = false
    local validated_charset

    for index = 1, #value + 1 do
        local char = value:sub(index, index)
        if index > #value or (char == ";" and not quoted) then
            if parameter_start then
                local parameter = value:sub(parameter_start, index - 1)
                local name, charset = parameter:match(
                    "^%s*([^=%s]+)%s*=%s*(.-)%s*$")
                if name and name:lower() == "charset" then
                    charset = charset:match("^%s*(.-)%s*$")
                    if charset:sub(1, 1) == '"' and charset:sub(-1) == '"' then
                        charset = charset:sub(2, -2)
                    end
                    charset = charset:lower()
                    if charset ~= "utf-8" and charset ~= "utf8" then
                        return true
                    end
                    validated_charset = "UTF-8"
                end
            end
            parameter_start = index + 1
        elseif char == '"' and not escaped then
            quoted = not quoted
        end

        if char == "\\" and quoted and not escaped then
            escaped = true
        else
            escaped = false
        end
    end
    return false, validated_charset
end


function _M.rewrite(plugin_name, conf, ctx, sign)
    if type(conf) ~= "table" then
        core.log.error(plugin_name, " configuration is missing")
        return 500, {message = "internal_error"}
    end

    if not contains(conf.request.methods, ngx.req.get_method()) then
        return
    end

    -- Secure by default: only an explicit `require_consumer = false` lets
    -- requests without an authenticated Consumer be signed.
    if conf.request.require_consumer ~= false and not (ctx and ctx.consumer) then
        core.log.warn(plugin_name, " rejected request: no authenticated Consumer")
        return 401, {message = "unauthorized"}
    end

    local headers = ngx.req.get_headers(0)
    local content_encoding = headers["content-encoding"]
    if content_encoding ~= nil
       and (type(content_encoding) ~= "string"
            or content_encoding:lower():match("^%s*(.-)%s*$") ~= "identity") then
        return 415, {message = "unsupported_media_type"}
    end
    local content_type_header = headers["content-type"]
    if type(content_type_header) ~= "string" then
        return 415, {message = "unsupported_media_type"}
    end
    local content_type = normalized_content_type(content_type_header)
    local accepted = false
    for _, configured_type in ipairs(conf.request.content_types) do
        if configured_type:lower() == content_type then
            accepted = true
            break
        end
    end
    if not accepted then
        return 415, {message = "unsupported_media_type"}
    end
    local unsupported_charset, charset = has_unsupported_charset(content_type_header)
    if unsupported_charset then
        return 415, {message = "unsupported_media_type"}
    end

    if not runtime_ok then
        core.log.error(plugin_name, " requires APISIX-Runtime to limit request body size")
        return 501, {message = "internal_error"}
    end
    local max_body_bytes = effective_body_limit(ctx, conf.request.max_body_bytes)
    local limit_ok, limit_err = apisix_ngx_client.set_client_max_body_size(
        max_body_bytes)
    if not limit_ok then
        core.log.error(plugin_name, " failed to set client max body size: ", limit_err)
        return 503, {message = "internal_error"}
    end

    local body, body_err, body_err_code = core.request.get_body(max_body_bytes, ctx)
    if not body then
        if not body_err then
            core.log.warn(plugin_name, " failed to read request body: ", body_err)
            return 400, {message = "empty_body"}
        end
        if body_err_code == "too_large" then
            core.log.warn(plugin_name, " failed to read request body: ", body_err)
            return 413, {message = "body_too_large"}
        end
        core.log.error(plugin_name, " failed to read request body: ", body_err)
        return 500, {message = "internal_error"}
    end

    if conf.signature.algorithm == "rsa-sha1" then
        core.log.warn(plugin_name, " is using legacy SHA-1 cryptography")
    end

    if body == "" then
        return 400, {message = "empty_body"}
    end

    local signed, code, detail = sign(body, conf, charset)
    if not signed then
        local internal_error = not code or code == "credential_error" or code == "signing_error"
        -- Client-caused rejections are logged at warn level so that malformed
        -- requests cannot flood the error log.
        local log = internal_error and core.log.error or core.log.warn
        log(plugin_name, " rejected request: ", code, ": ", detail)
        local status = internal_error and 500 or 400
        return status, {message = code or "internal_error"}
    end

    ngx.req.set_body_data(signed)
    local var_cache = ctx and ctx.var and ctx.var._cache
    if var_cache then
        var_cache.http_content_length = nil
    end
    core.request.set_header(ctx, "Content-Length", tostring(#signed))
    core.request.set_header(ctx, "Transfer-Encoding", nil)
    for _, header in ipairs(BODY_DIGEST_HEADERS) do
        core.request.set_header(ctx, header, nil)
    end
end


return _M
