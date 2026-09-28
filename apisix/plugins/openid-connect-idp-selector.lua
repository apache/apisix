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

local core  = require("apisix.core")
local jwt   = require("resty.jwt")
local ipairs = ipairs
local type  = type

local plugin_name = "openid-connect-idp-selector"

local schema = {
    type = "object",
    properties = {
        configs = {
            type = "array",
            description = "candidate openid-connect configs; the first entry " ..
                           "whose \"key\" equals the bearer token's \"iss\" claim is selected",
            minItems = 1,
            items = {
                type = "object",
                properties = {
                    key = {type = "string"},
                    discovery = {type = "string"},
                    client_id = {type = "string"},
                    client_secret = {type = "string"},
                },
                required = {"key", "discovery", "client_id", "client_secret"},
            },
        },
    },
    required = {"configs"},
    encrypt_fields = {"configs.client_secret"},
}

local _M = {
    version = 0.1,
    priority = 2895,
    name = plugin_name,
    schema = schema,
}


function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end


-- Reads the bearer token's "iss" claim without verifying its signature -
-- real verification happens later, in openid-connect, against whichever
-- config this match selects. A malformed/missing/unsigned-looking token
-- just yields no match, and no config is selected.
function _M.rewrite(conf, ctx)
    local auth_header = core.request.header(ctx, "Authorization")
    if not auth_header then
        return
    end

    local token = auth_header:match("^[Bb]earer%s+(.+)$")
    if not token then
        return
    end

    local jwt_obj = jwt:load_jwt(token)
    if not jwt_obj or not jwt_obj.valid or type(jwt_obj.payload) ~= "table" then
        return
    end

    local iss = jwt_obj.payload.iss
    for _, config in ipairs(conf.configs) do
        if config.key == iss then
            ctx.var.oidc_discovery = config.discovery
            ctx.var.oidc_client_id = config.client_id
            ctx.var.oidc_client_secret = config.client_secret
            return
        end
    end
end


return _M
