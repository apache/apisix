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
local core     = require("apisix.core")

local _M = {}

local function get_full_log(ngx)

    local ctx = ngx.ctx.api_ctx
    local var = ctx.var

    local url = var.scheme .. "://" .. var.host .. ":" .. var.server_port .. var.request_uri

    local service_name
    local vars = var
    if ctx.matched_route and ctx.matched_route.value then
        service_name = ctx.matched_route.value.desc or
                ctx.matched_route.value.id
    else
        service_name = vars.host
    end

    return  {
        request = {
            url = url,
            uri = var.request_uri,
            method = ngx.req.get_method(),
            headers = ngx.req.get_headers(),
            querystring = ngx.req.get_uri_args(),
            size = var.request_length
        },
        response = {
            status = ngx.status,
            headers = ngx.resp.get_headers(),
            size = var.bytes_sent
        },
        upstream = var.upstream_addr,
        service = service_name,
        consumer = ctx.consumer,
        client_ip = core.request.get_remote_client_ip(ngx.ctx.api_ctx),
        start_time = ngx.req.start_time() * 1000,
        latency = (ngx.now() - ngx.req.start_time()) * 1000
    }
end

_M.get_full_log = get_full_log

return _M
