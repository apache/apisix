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


function _M.configure_request(conf, request_table, ctx)
    local ups_host = DEFAULT_HOST
    if conf.override and conf.override.host and conf.override.host ~= "" then
        ups_host = conf.override.host
    end
    local ups_port = DEFAULT_PORT
    if conf.override and conf.override.port and conf.override.host ~= "" then
        ups_port = conf.override.port
    end
    local upstream_addr = ups_host .. ":" .. ups_port
    core.log.info("modified upstream address: ", upstream_addr)
    local upstream_node = {
        nodes = {
            [upstream_addr] = 1
        },
        pass_host = "node",
        scheme = test_scheme or "https",
        vid = "openai",
    }
    upstream.set_upstream(upstream_node, ctx)

    local ups_path = (conf.override and conf.override.path)
                        or path_mapper[conf.route_type]
    ngx.var.upstream_uri = ups_path
    ngx.req.set_method(ngx.HTTP_POST)
    if conf.auth.source == "header" then
        core.request.set_header(ctx, conf.auth.name, conf.auth.value)
    else
        local args = core.request.get_uri_args(ctx)
        args[conf.auth.name] = conf.auth.value
        core.request.set_uri_args(ctx, args)
    end

    if conf.model.options then
        for opt, val in pairs(conf.model.options) do
            request_table[opt] = val
        end
    end
    return true
end

return _M
