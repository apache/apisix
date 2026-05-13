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
local require = require
local pcall = pcall
local core = require("apisix.core")
local constants = require("apisix.constants")

local is_resty_saml_init = false
local resty_saml

local lrucache = core.lrucache.new({
    ttl = 300, count = 512
})

local schema = {
    type = "object",
    properties = {
        sp_issuer = { type = "string" },
        idp_uri = { type = "string" },
        idp_cert = { type = "string" },
        login_callback_uri = { type = "string" },
        logout_uri = { type = "string" },
        logout_callback_uri = { type = "string" },
        logout_redirect_uri = { type = "string" },
        sp_cert = { type = "string" },
        sp_private_key = { type = "string" },
        auth_protocol_binding_method = {
            type = "string",
            default = "HTTP-Redirect",
            enum = {"HTTP-Redirect", "HTTP-POST",},
            description = "Binding method for authentication protocol, setting to HTTP-POST " ..
                           "will set cookie samesite to None and cookie secure to true"
        },
        secret = {
            type = "string",
            description = "Secret used for key derivation.",
            minLength = 8,
            maxLength = 32,
        },
        secret_fallbacks = {
            type = "array",
            items = {
                type = "string",
                minLength = 8,
                maxLength = 32,
            },
            description = "List of secrets for alternative secrets used when doing key rotation"
        }
    },
    encrypt_fields = {"sp_private_key", "secret", "secret_fallbacks"},
    required = {
        "sp_issuer",
        "idp_uri",
        "idp_cert",
        "login_callback_uri",
        "logout_uri",
        "logout_callback_uri",
        "logout_redirect_uri",
        "sp_cert",
        "sp_private_key",
    }
}

local plugin_name = "saml-auth"

local _M = {
    version = 0.1,
    priority = 2598,
    name = plugin_name,
    schema = schema,
}


local function load_resty_saml()
    if resty_saml then
        return resty_saml
    end

    local ok, saml = pcall(require, "resty.saml")
    if not ok then
        return nil, saml
    end

    resty_saml = saml
    return resty_saml
end

function _M.check_schema(conf, _)
    return core.schema.check(schema, conf)
end

function _M.rewrite(conf, ctx)
    local saml_lib, err = load_resty_saml()
    if not saml_lib then
        core.log.error("failed to load lua-resty-saml: ", err)
        return 503, {message = "lua-resty-saml is required for saml-auth"}
    end

    if not is_resty_saml_init then
        local err = saml_lib.init({
            debug = false,
            data_dir = constants.apisix_lua_home .. "/deps/share/lua/5.1/resty/saml"
        })
        if err then
            core.log.error("saml init: ", err)
            return 503, {message = "saml init failed"}
        end
        is_resty_saml_init = true
    end

    local saml = core.lrucache.plugin_ctx(lrucache, ctx, nil, saml_lib.new, conf)
    if not saml then
        core.log.error("saml new failed")
        return 500, {message = "create saml object failed"}
    end

    local data, err = saml:authenticate()
    if err then
        core.log.error("saml authenticate failed: ", err)
        return 500, {message = "saml authentication failed"}
    end

    ctx.external_user = data
end

return _M
