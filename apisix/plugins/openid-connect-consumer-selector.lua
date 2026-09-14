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
local pcall = pcall
local type  = type

local plugin_name = "openid-connect-consumer-selector"

local schema = {
    type = "object",
    properties = {
        match_source = {
            type = "string",
            description = "where to read the value that selects a config entry: " ..
                           "\"var\" reads a request-context variable named by match_var; " ..
                           "\"token_iss\" decodes the bearer token's \"iss\" claim " ..
                           "without verifying its signature (verification happens " ..
                           "later, in openid-connect, against the selected config)",
            enum = {"var", "token_iss"},
            default = "var",
        },
        match_var = {
            type = "string",
            description = "name of the request-context variable whose value " ..
                           "selects a config entry, e.g. \"http_x_tenant_id\"; " ..
                           "required when match_source is \"var\"",
        },
        configs = {
            type = "array",
            description = "candidate openid-connect configs; the first entry " ..
                           "whose \"key\" equals the resolved match value is selected",
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
    ["if"] = {
        properties = {
            match_source = {enum = {"var"}},
        },
    },
    ["then"] = {
        required = {"match_var"},
    },
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


local function select_config(configs, match_value)
    if match_value == nil then
        return nil
    end

    for _, config in ipairs(configs) do
        if config.key == match_value then
            return config
        end
    end

    return nil
end


-- Reads the bearer token's "iss" claim without verifying its signature -
-- real verification happens later, in openid-connect, against whichever
-- config this match selects. A malformed/missing/unsigned-looking token
-- just yields no match, same as an unrecognized value in "var" mode.
local function resolve_match_value_from_token_iss(ctx)
    local auth_header = core.request.header(ctx, "Authorization")
    if not auth_header then
        return nil
    end

    local token = auth_header:match("^[Bb]earer%s+(.+)$")
    if not token then
        return nil
    end

    local jwt_obj = jwt:load_jwt(token)
    if not jwt_obj or not jwt_obj.valid or type(jwt_obj.payload) ~= "table" then
        return nil
    end

    return jwt_obj.payload.iss
end


local function resolve_match_value_from_var(conf, ctx)
    -- match_var is only required by the schema when match_source is
    -- explicitly "var" (its own default); a conf that omits match_source
    -- entirely still lands here and could have no match_var at all
    if not conf.match_var then
        return nil
    end

    -- an unrecognized variable name (e.g. a typo in match_var) can raise
    -- instead of returning nil, so this must not crash the request; treat
    -- it the same as "no match" and let openid-connect fail closed
    local ok, match_value = pcall(function() return ctx.var[conf.match_var] end)
    if not ok then
        core.log.warn("openid-connect-consumer-selector: failed to read var \"",
                       conf.match_var, "\": ", match_value)
        return nil
    end

    return match_value
end


function _M.rewrite(conf, ctx)
    local match_value
    if conf.match_source == "token_iss" then
        match_value = resolve_match_value_from_token_iss(ctx)
    else
        match_value = resolve_match_value_from_var(conf, ctx)
    end

    local config = select_config(conf.configs, match_value)
    if not config then
        return
    end

    ctx.var.oidc_discovery = config.discovery
    ctx.var.oidc_client_id = config.client_id
    ctx.var.oidc_client_secret = config.client_secret
end


return _M
