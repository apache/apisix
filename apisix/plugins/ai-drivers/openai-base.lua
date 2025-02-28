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

local mt = {
    __index = _M
}

local core = require("apisix.core")
local http = require("resty.http")
local url  = require("socket.url")

local pairs = pairs
local type  = type
local setmetatable = setmetatable


function _M.new(opts)

    local self = {
        host = opts.host,
        port = opts.port,
        path = opts.path,
    }
    return setmetatable(self, mt)
end


function _M.request(self, conf, request_table, extra_opts)
    local httpc, err = http.new()
    if not httpc then
        return nil, "failed to create http client to send request to LLM server: " .. err
    end
    httpc:set_timeout(conf.timeout)

    local endpoint = extra_opts.endpoint
    local parsed_url
    if endpoint then
        parsed_url = url.parse(endpoint)
    end

    local ok, err = httpc:connect({
        scheme = endpoint and parsed_url.scheme or "https",
        host = endpoint and parsed_url.host or self.host,
        port = endpoint and parsed_url.port or self.port,
        ssl_verify = conf.ssl_verify,
        ssl_server_name = endpoint and parsed_url.host or self.host,
        pool_size = conf.keepalive and conf.keepalive_pool,
    })

    if not ok then
        return nil, "failed to connect to LLM server: " .. err
    end

    local query_params = extra_opts.query_params

    if type(parsed_url) == "table" and parsed_url.query and #parsed_url.query > 0 then
        local args_tab = core.string.decode_args(parsed_url.query)
        if type(args_tab) == "table" then
            core.table.merge(query_params, args_tab)
        end
    end

    local path = (endpoint and parsed_url.path or self.path)

    local headers = extra_opts.headers
    headers["Content-Type"] = "application/json"
    local params = {
        method = "POST",
        headers = headers,
        keepalive = conf.keepalive,
        ssl_verify = conf.ssl_verify,
        path = path,
        query = query_params
    }

    if extra_opts.model_options then
        for opt, val in pairs(extra_opts.model_options) do
            request_table[opt] = val
        end
    end

    local req_json, err = core.json.encode(request_table)
    if not req_json then
        return nil, err
    end

    params.body = req_json

    httpc:set_timeout(conf.keepalive_timeout)
    local res, err = httpc:request(params)
    if not res then
        return nil, err
    end

    return res, nil, httpc
end

return _M
