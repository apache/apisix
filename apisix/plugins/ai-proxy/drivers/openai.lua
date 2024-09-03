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
local _M = {}

local core = require("apisix.core")
local http = require("resty.http")
local test_scheme = os.getenv("AI_PROXY_TEST_SCHEME")
local upstream = require("apisix.upstream")
local ngx = ngx
local pairs = pairs

-- globals
local DEFAULT_HOST = "api.openai.com"
local DEFAULT_PORT = 443

local path_mapper = {
    ["llm/chat"] = "/v1/chat/completions",
}

function _M.request(conf, request_table, ctx)
    local httpc, err = http.new()
    if not httpc then
        return nil, "failed to create http client to send request to LLM server: " .. err
    end
    httpc:set_timeout(conf.timeout)

    local custom_host = core.table.try_read_attr(conf, "override", "host")
    local custom_port = core.table.try_read_attr(conf, "override", "port")

    local ok, err = httpc:connect({
        scheme = test_scheme or "https",
        host = custom_host or DEFAULT_HOST,
        port = custom_port or DEFAULT_PORT,
        ssl_verify = conf.ssl_verify,
        ssl_server_name = custom_host or DEFAULT_HOST,
        pool_size = conf.keepalive and conf.keepalive_pool,
    })

    if not ok then
        return nil, "failed to connect to LLM server: " .. err
    end

    local params = {
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
        },
        keepalive = conf.keepalive,
        ssl_verify = conf.ssl_verify,
        path = "/v1/chat/completions",
    }

    if conf.auth.type == "header" then
        params.headers[conf.auth.name] = conf.auth.value
    end

    if conf.model.options then
        for opt, val in pairs(conf.model.options) do
            request_table[opt] = val
        end
    end
    params.body = core.json.encode(request_table)

    local res, err = httpc:request(params)
    if not res then
        return 500, "failed to send request to LLM server: " .. err
    end

    -- TOOD: keepalive maintainance
    return res, nil, httpc
end

return _M
