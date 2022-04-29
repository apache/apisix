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
local ext = require("apisix.plugins.ext-plugin.init")
local constants = require("apisix.constants")
local http = require("resty.http")


local name = "ext-plugin-post-resp"
local _M = {
    version = 0.1,
    priority = -4000,
    name = name,
    schema = ext.schema,
}


local function get_response(ctx)
    local httpc = http.new()
    local ok, err = httpc:connect({
        scheme = ctx.upstream_scheme,
        host = ctx.picked_server.host,
        port = ctx.picked_server.port,
    })

    if not ok then
        return nil, err
    end

    local params = {
        path = ctx.var.uri,
        headers = core.request.headers(ctx),
        method = core.request.get_method(ctx),
    }

    local body, err = core.request.get_body()
    if err then
        return nil, err
    end

    if body then
        params["body"] = body
    end

    if ctx.var.is_args == "?" then
        params["query"] = ctx.var.args or ""
    end

    local res, err = httpc:request(params)
    if not res then
        return nil, err
    end
    return res, err
end


function _M.check_schema(conf)
    return core.schema.check(_M.schema, conf)
end


function _M.response(conf, ctx)
     -- TODO: request
     local res, err = get_response(ctx)
    if not res or err then
        core.log.error("failed to request: ", err or "")
        return core.response.exit(503)
    end
    ctx.runner_ext_response = res

    core.log.info("response info, status: ", res.status)
     local headers = res.headers
     local code, body = ext.communicate(conf, ctx, name, constants.RPC_HTTP_RESP_CALL)
     if code or body then
         -- TODO: chunk
         return code, body
     end
     core.log.info("ext-plugin will send response")
     -- send origin response
     -- TODO: chunk
     core.response.set_header(headers)
     local body = res.body_reader()
     core.log.info("response body chunk: ", body)

     return res.status, body
end


return _M
