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
local http = require "resty.http"
local sub_str  = string.sub
local plugin_name = "authz-keycloak"
local url = require "net.url"
local tostring = tostring


local schema = {
    type = "object",
    properties = {
        token_endpoint = {type = "string"},
        permissions = {type = "string"},
        grant_type = {type = "string"},
        audience = {type = "string"},
        response_mode = {type = "string"},
        timeout = {type = "integer", minimum = 1, default = 3},
        enforcement_mode = {
            type = "string",
            enum = {"ENFORCING", "PERMISSIVE"}
        }
    },
    required = {"token_endpoint", "grant_type"}
}


local _M = {
    version = 0.1,
    priority = 2000,
    type = 'auth',
    name = plugin_name,
    schema = schema,
}

function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    return true
end


local function send_http_data(conf, token)
    local url_decoded = url.parse(conf.token_endpoint)
    local host = url_decoded.host
    local port = url_decoded.port

    if ((not port) and url_decoded.scheme == "https") then
        port = 443
    elseif not port then
        port = 80
    end

    local httpc = http.new()
    local httpc_res, httpc_err = httpc:request_uri(conf.token_endpoint, {
        method = "POST",
        body = "grant_type=" .. conf.grant_type .. "&audience="
            .. conf.audience .. "&permission=" .. conf.permissions,
        headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            ["Authorization"] = token
        },
        keepalive_timeout = 60000,
        keepalive_pool = 10
    })

    if not httpc_res then
        core.response.exit(500, httpc_err)
        core.log.error("error while sending data to [" .. host .. "] port["
            .. tostring(port) .. "] " .. httpc_err)
        return
    end

     --reject the call
    if httpc_res.status >= 400 then
        core.log.error("400 occurred here" .. core.json.encode(httpc_res.body) .. "")
        core.response.exit(httpc_res.status, httpc_res.body)
    end
end


local function fetch_jwt_token(ctx)
    local token = core.request.header(ctx, "authorization")
    if token then
        local prefix = sub_str(token, 1, 7)
        if prefix ~= 'Bearer ' and prefix ~= 'bearer ' then
            return "Bearer " .. token
        end
        return token
    else
        return nil, "authorization header not available"
    end
end


function _M.rewrite(conf, ctx)
    local jwt_token, err = fetch_jwt_token(ctx)
    if not jwt_token then
        core.log.error("failed to fetch JWT token: ", err)
        return 401, {message = "Missing JWT token in request"}
    end

    --core.log.error('The token is' .. jwt_token)
    send_http_data(conf, jwt_token)
    core.log.debug("hit keycloak-auth rewrite")
end


return _M
