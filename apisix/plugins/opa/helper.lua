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
local ngx_time = ngx.time

local _M = {}


local function build_var(conf, ctx)
    return {
        server_addr = ctx.var.server_addr,
        server_port = ctx.var.server_port,
        remote_addr = ctx.var.remote_addr,
        remote_port = ctx.var.remote_port,
        timestamp   = ngx_time(),
    }
end


local function build_http_request(conf, ctx)
    return {
        scheme  = core.request.get_scheme(ctx),
        method  = core.request.get_method(ctx),
        host    = core.request.get_host(ctx),
        port    = core.request.get_port(ctx),
        path    = core.request.get_path(ctx),
        headers = core.request.headers(ctx),
        query   = core.request.get_uri_args(ctx),
    }
end


function _M.build_opa_input(conf, ctx, subsystem)
    local request = build_http_request(conf, ctx)

    local data = {
        type    = subsystem,
        request = request,
        var     = build_var(conf, ctx)
    }

    return core.json.encode({input = data})
end


return _M
