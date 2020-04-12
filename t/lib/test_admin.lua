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
local http = require("resty.http")
local json = require("cjson.safe")
local dir_names = {}


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
    if type(left_tab) == "string" then
        left_tab = json.decode(left_tab)
    end
    if type(right_tab) == "string" then
        right_tab = json.decode(right_tab)
    end

    local ok, err = com_tab(left_tab, right_tab)
    if not ok then
        return 500, "failed, " .. err
    end

    return true
end


function _M.test(uri, method, body, pattern)
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
            headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            },
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


return _M
