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
local ngx = ngx

-- globals
local DEFAULT_HOST = "api.openai.com"
local DEFAULT_PORT = 443

local path_mapper = {
    ["llm/completions"] = "/v1/completions",
    ["llm/chat"] = "/v1/chat/completions",
}


function _M.configure_request(conf, request_table, ctx)
    local ip, err = core.resolver.parse_domain(conf.model.options.upstream_host or DEFAULT_HOST)
    if not ip then
        core.log.error("failed to resolve ai_proxy upstream host: ", err)
        return core.response.exit(500)
    end
    ctx.custom_upstream_ip = ip
    ctx.custom_upstream_port = conf.model.options.upstream_port or DEFAULT_PORT

    local ups_path = (conf.model.options and conf.model.options.upstream_path)
                        or path_mapper[conf.route_type]
    ngx.var.upstream_uri = ups_path
    ngx.var.upstream_scheme = test_scheme or "https"
    ngx.req.set_method(ngx.HTTP_POST)
    ngx.var.upstream_host = conf.model.options.upstream_host or DEFAULT_HOST
    ctx.custom_balancer_host = conf.model.options.upstream_host or DEFAULT_HOST
    ctx.custom_balancer_port = conf.model.options.port or DEFAULT_PORT
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
    return true, nil
end

return _M
