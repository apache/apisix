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
local http              = require("resty.http")
local json              = require("cjson.safe")
local core              = require("apisix.core")
local aes               = require "resty.aes"
local ngx_encode_base64 = ngx.encode_base64
local str_find          = string.find
local dir_names         = {}


local _M = {}


local function com_tab(pattern, data, deep)
    deep = deep or 1

    for k, v in pairs(pattern) do
        dir_names[deep] = k

        if v == ngx.null then
            v = nil
        end

        if type(v) == "table" then
            local ok, err = com_tab(v, data[k], deep + 1)
            if not ok then
                return false, err
            end

        elseif v ~= data[k] then
            return false, "path: " .. table.concat(dir_names, "->", 1, deep)
                          .. " expect: " .. tostring(v) .. " got: "
                          .. tostring(data[k])
        end
    end

    return true
end


local methods = {
    [ngx.HTTP_GET    ] = "GET",
    [ngx.HTTP_HEAD   ] = "HEAD",
    [ngx.HTTP_PUT    ] = "PUT",
    [ngx.HTTP_POST   ] = "POST",
    [ngx.HTTP_DELETE ] = "DELETE",
    [ngx.HTTP_OPTIONS] = "OPTIONS",
    [ngx.HTTP_PATCH]   = "PATCH",
    [ngx.HTTP_TRACE] = "TRACE",
}


function _M.test_ipv6(uri)
    local sock = ngx.socket.tcp()
    local ok, err = sock:connect("[::1]", 12345)
    if not ok then
        ngx.say("failed to connect: ", err)
        return
    end

    ngx.say("connected: ", ok)

    local req = "GET " .. uri .. " HTTP/1.0\r\nHost: localhost\r\n"
                .. "Connection: close\r\n\r\n"
    -- req = "OK"
    -- ngx.log(ngx.WARN, "req: ", req)

    local bytes, err = sock:send(req)
    if not bytes then
        ngx.say("failed to send request: ", err)
        return
    end

    ngx.say("request sent: ", bytes)

    while true do
        local line, err, part = sock:receive()
        if line then
            ngx.say("received: ", line)

        else
            ngx.say("failed to receive a line: ", err, " [", part, "]")
            break
        end
    end

    ok, err = sock:close()
    ngx.say("close: ", ok, " ", err)
end


function _M.comp_tab(left_tab, right_tab)
    local err
    dir_names = {}

    if type(left_tab) == "string" then
        left_tab, err = json.decode(left_tab)
        if not left_tab then
            return false, "failed to decode expected data: " .. err
        end
    end
    if type(right_tab) == "string" then
        right_tab, err  = json.decode(right_tab)
        if not right_tab then
            return false, "failed to decode expected data: " .. err
        end
    end

    local ok, err = com_tab(left_tab, right_tab)
    if not ok then
        return false, err
    end

    return true
end


function _M.test(uri, method, body, pattern, headers)
    if not headers then
        headers = {}
    end
    if not headers["Content-Type"] then
        headers["Content-Type"] = "application/x-www-form-urlencoded"
    end

    if type(body) == "table" then
        body = json.encode(body)
    end

    if type(pattern) == "table" then
        pattern = json.encode(pattern)
    end

    if type(method) == "number" then
        method = methods[method]
    end

    local httpc = http.new()
    -- https://github.com/ledgetech/lua-resty-http
    uri = ngx.var.scheme .. "://" .. ngx.var.server_addr
          .. ":" .. ngx.var.server_port .. uri
    local res, err = httpc:request_uri(uri,
        {
            method = method,
            body = body,
            keepalive = false,
            headers = headers,
        }
    )
    if not res then
        ngx.log(ngx.ERR, "failed http: ", err)
        return nil, err
    end

    if res.status >= 300 then
        return res.status, res.body
    end

    if pattern == nil then
        return res.status, "passed", res.body
    end

    local res_data = json.decode(res.body)
    local ok, err = _M.comp_tab(pattern, res_data)
    if not ok then
        return 500, "failed, " .. err, res_data
    end

    return 200, "passed", res_data
end


function _M.read_file(path)
    local f = assert(io.open(path, "rb"))
    local cert = f:read("*all")
    f:close()
    return cert
end


function _M.req_self_with_http(uri, method, body, headers)
    if type(body) == "table" then
        body = json.encode(body)
    end

    if type(method) == "number" then
        method = methods[method]
    end
    headers = headers or {}

    local httpc = http.new()
    -- https://github.com/ledgetech/lua-resty-http
    uri = ngx.var.scheme .. "://" .. ngx.var.server_addr
          .. ":" .. ngx.var.server_port .. uri
    headers["Content-Type"] = "application/x-www-form-urlencoded"
    local res, err = httpc:request_uri(uri,
        {
            method = method,
            body = body,
            keepalive = false,
            headers = headers,
        }
    )

    return res, err
end


function _M.aes_encrypt(origin)
    local iv = "1234567890123456"
    local aes_128_cbc_with_iv = assert(aes:new(iv, nil, aes.cipher(128, "cbc"), {iv=iv}))

    if aes_128_cbc_with_iv ~= nil and str_find(origin, "---") then
        local encrypted = aes_128_cbc_with_iv:encrypt(origin)
        if encrypted == nil then
            core.log.error("failed to encrypt key[", origin, "] ")
            return origin
        end

        return ngx_encode_base64(encrypted)
    end

    return origin
end


return _M
