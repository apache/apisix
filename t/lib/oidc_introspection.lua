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
local test_admin = require("lib.test_admin").test


local _M = {}


local function request_uri(uri, opts)
    local res, err = http.new():request_uri(uri, opts)
    if not res then
        error(err)
    end
    return res
end


function _M.configure(mode, timeout)
    local endpoint = "http://127.0.0.1:1970/introspect?mode=" .. mode
    if mode == "unreachable" then
        endpoint = "http://127.0.0.1:1979/introspect"
    end

    local route = {
        uri = "/protected",
        plugins = {
            ["openid-connect"] = {
                client_id = "test-client",
                client_secret = "test-secret",
                discovery = "http://127.0.0.1:1970/.well-known/openid-configuration",
                introspection_endpoint = endpoint,
                introspection_endpoint_auth_method = "client_secret_post",
                introspection_interval = 60,
                bearer_only = true,
                ssl_verify = false,
                timeout = timeout or 3,
            },
        },
        upstream = {
            type = "roundrobin",
            nodes = {
                ["127.0.0.1:1970"] = 1,
            },
        },
    }

    local code, body = test_admin(
        "/apisix/admin/routes/oidc-introspection", ngx.HTTP_PUT,
        core.json.encode(route))
    if code >= 300 then
        error(body)
    end

    ngx.sleep(0.5)
    request_uri("http://127.0.0.1:1970/reset")
end


local function introspect(token)
    local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/protected"
    local res = request_uri(uri, {
        method = "GET",
        headers = {
            Authorization = "Bearer " .. token,
        },
    })
    local challenge = res.headers["WWW-Authenticate"] or
                      res.headers["www-authenticate"] or ""
    return res.status, challenge:find('error="invalid_token"', 1, true) ~= nil
end


function _M.request(token)
    return introspect(token)
end


function _M.concurrent(token, count, stagger_after_first)
    local threads = {}
    for i = 1, count do
        threads[i] = assert(ngx.thread.spawn(introspect, token))
        if i == 1 and stagger_after_first then
            local deadline = ngx.now() + 2
            repeat
                ngx.sleep(0.01)
            until _M.upstream_calls() == 1 or ngx.now() >= deadline
            ngx.sleep(stagger_after_first)
        end
    end

    local statuses = {}
    local invalid_token_challenges = 0
    for _, thread in ipairs(threads) do
        local ok, status, invalid_token = ngx.thread.wait(thread)
        if not ok then
            error(status)
        end
        statuses[status] = (statuses[status] or 0) + 1
        if invalid_token then
            invalid_token_challenges = invalid_token_challenges + 1
        end
    end

    return statuses, invalid_token_challenges
end


function _M.upstream_calls()
    local res = request_uri("http://127.0.0.1:1970/calls")
    return tonumber(res.body)
end


return _M
