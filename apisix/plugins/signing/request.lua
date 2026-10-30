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

local ipairs = ipairs
local ngx = ngx
local tostring = tostring
local type = type

local _M = {}

local BODY_DIGEST_HEADERS = {
    "Content-MD5",
    "Digest",
    "Content-Digest",
    "Repr-Digest",
}


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
    return normalized and normalized:lower() or ""
end


local function has_unsupported_charset(value)
    if not value then
        return false
    end

    local parameter_start
    local quoted = false
    local escaped = false

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
    return false
end


function _M.rewrite(plugin_name, conf, ctx, sign)
    if type(conf) ~= "table" then
        return 500, {message = "internal_error"}
    end

    conf.request = conf.request or {}
    conf.request.methods = conf.request.methods or {"POST"}
    conf.request.content_types = conf.request.content_types or {"application/xml"}
    conf.request.max_body_bytes = conf.request.max_body_bytes or 5242880

    if not contains(conf.request.methods, ngx.req.get_method()) then
        return
    end

    local content_type_header = core.request.header(ctx, "Content-Type")
    local content_type = normalized_content_type(content_type_header)
    if not contains(conf.request.content_types, content_type) then
        return 415, {message = "unsupported_media_type"}
    end
    if has_unsupported_charset(content_type_header) then
        return 415, {message = "unsupported_media_type"}
    end

    local body, body_err = core.request.get_body(conf.request.max_body_bytes, ctx)
    if not body then
        core.log.error(plugin_name, " failed to read request body: ", body_err)
        if not body_err then
            return 400, {message = "empty_body"}
        end
        if body_err:find("is greater than the maximum size", 1, true) then
            return 413, {message = "body_too_large"}
        end
        return 500, {message = "internal_error"}
    end

    if conf.signature.algorithm == "rsa-sha1" then
        core.log.warn(plugin_name, " is using legacy SHA-1 cryptography")
    end

    local signed, code = sign(body, conf)
    if not signed then
        core.log.error(plugin_name, " rejected request: ", code)
        local internal_error = code == "credential_error" or code == "signing_error"
        local status = internal_error and 500 or 400
        return status, {message = code or "internal_error"}
    end

    ngx.req.set_body_data(signed)
    core.request.set_header(ctx, "Content-Length", tostring(#signed))
    ngx.req.clear_header("Transfer-Encoding")
    for _, header in ipairs(BODY_DIGEST_HEADERS) do
        ngx.req.clear_header(header)
    end
end


return _M