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
local core      = require("apisix.core")
local http      = require "resty.http"
local sub_str   = string.sub
local url       = require "net.url"
local tostring  = tostring
local ngx       = ngx
local plugin_name = "authz-keycloak0"
local openidc = require("resty.openidc")
local cjson = require("cjson")
local cjson_s = require("cjson.safe")



local schema = {
    type = "object",
    properties = {
        token_endpoint = {type = "string", minLength = 1, maxLength = 4096},
        permissions = {
            type = "array",
            items = {
                type = "string",
                minLength = 1, maxLength = 100
            },
            uniqueItems = true
        },
        grant_type = {
            type = "string",
            default="urn:ietf:params:oauth:grant-type:uma-ticket",
            enum = {"urn:ietf:params:oauth:grant-type:uma-ticket"},
            minLength = 1, maxLength = 100
        },
        audience = {type = "string", minLength = 1, maxLength = 100},
        timeout = {type = "integer", minimum = 1000, default = 3000},
        policy_enforcement_mode = {
            type = "string",
            enum = {"ENFORCING", "PERMISSIVE"},
            default = "ENFORCING"
        },
        keepalive = {type = "boolean", default = true},
        keepalive_timeout = {type = "integer", minimum = 1000, default = 60000},
        keepalive_pool = {type = "integer", minimum = 1, default = 5},
        ssl_verify = {type = "boolean", default = true},
        client_id = {type = "string", minLength = 1, maxLength = 100},
        client_secret = {type = "string", minLength = 1, maxLength = 100},
        resource_set_endpoint = {type = "string", minLength = 1, maxLength = 4096},
    },
    required = {"token_endpoint"}
}


local _M = {
    version = 0.1,
    priority = 2000,
    name = plugin_name,
    schema = schema,
}

function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end

local function is_path_protected(conf)
    -- TODO if permissions are empty lazy load paths from Keycloak
    if conf.permissions == nil then
        return false
    end
    return true
end


local function evaluate_permissions(conf, token, uri)
    local url_decoded = url.parse(conf.token_endpoint)
    local host = url_decoded.host
    local port = url_decoded.port

    if not port then
        if url_decoded.scheme == "https" then
            port = 443
        else
            port = 80
        end
    end

    if not is_path_protected(conf) and conf.policy_enforcement_mode == "ENFORCING" then
        return 403
    end

    -- Get access token for Protection API.

    core.log.error("Getting access token for Protection API.")
    local httpc = http.new()
    httpc:set_timeout(conf.timeout)

    local params = {
        method = "POST",
        body =  ngx.encode_args({
            grant_type = "client_credentials",
            client_id = conf.client_id,
            client_secret = conf.client_secret,
        }),
        ssl_verify = conf.ssl_verify,
        headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded"
        }
    }

    if conf.keepalive then
        params.keepalive_timeout = conf.keepalive_timeout
        params.keepalive_pool = conf.keepalive_pool
    else
        params.keepalive = conf.keepalive
    end

    core.log.error("Sending request to token endpoint to obtain access token.")
    local httpc_res, httpc_err = httpc:request_uri(conf.token_endpoint, params)
    core.log.error("Response body: ", httpc_res.body)
    local json = cjson_s.decode(httpc_res.body)
    core.log.error("Access token: ", json.access_token)
    core.log.error("Expires in: ", json.expires_in)
    core.log.error("Refresh token: ", json.refresh_token)
    core.log.error("Refresh expires in: ", json.refresh_expires_in)

    -- Get ID of resource trying to access.
    core.log.error("Request URI: ", uri)
    local httpc = http.new()
    httpc:set_timeout(conf.timeout)

    local params = {
        method = "GET",
        query = {uri = uri, matchingUri = "true"},
        ssl_verify = conf.ssl_verify,
        headers = {
            ["Auhtorization"] = json.access_token
        }
    }

    if conf.keepalive then
        params.keepalive_timeout = conf.keepalive_timeout
        params.keepalive_pool = conf.keepalive_pool
    else
        params.keepalive = conf.keepalive
    end

    core.log.error("Sending request to token endpoint to obtain access token.")
    local httpc_res, httpc_err = httpc:request_uri(conf.resource_set_endpoint, params)
    core.log.error("Response body: ", httpc_res.body)



    local httpc = http.new()
    httpc:set_timeout(conf.timeout)

    local params = {
        method = "POST",
        body =  ngx.encode_args({
            grant_type = conf.grant_type,
            audience = conf.audience,
            response_mode = "decision",
            permission = conf.permissions
        }),
        ssl_verify = conf.ssl_verify,
        headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            ["Authorization"] = token
        }
    }

    if conf.keepalive then
        params.keepalive_timeout = conf.keepalive_timeout
        params.keepalive_pool = conf.keepalive_pool
    else
        params.keepalive = conf.keepalive
    end

    local httpc_res, httpc_err = httpc:request_uri(conf.token_endpoint, params)

    if not httpc_res then
        core.log.error("error while sending authz request to [", host ,"] port[",
                        tostring(port), "] ", httpc_err)
        return 500, httpc_err
    end

    if httpc_res.status >= 400 then
        core.log.error("status code: ", httpc_res.status, " msg: ", httpc_res.body)
        return httpc_res.status, httpc_res.body
    end
end


local function fetch_jwt_token(ctx)
    local token = core.request.header(ctx, "Authorization")
    if not token then
        return nil, "authorization header not available"
    end

    local prefix = sub_str(token, 1, 7)
    if prefix ~= 'Bearer ' and prefix ~= 'bearer ' then
        return "Bearer " .. token
    end
    return token
end


function _M.access(conf, ctx)
    core.log.error("hit keycloak-auth access0")
    local jwt_token, err = fetch_jwt_token(ctx)
    if not jwt_token then
        core.log.error("failed to fetch JWT token: ", err)
        return 401, {message = "Missing JWT token in request"}
    end

    local status, body = evaluate_permissions(conf, jwt_token, ctx.var.request_uri)
    if status then
        return status, body
    end
end


return _M
