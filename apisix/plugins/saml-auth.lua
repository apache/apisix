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
local constants = require("apisix.constants")
local resty_saml = require("resty.saml")
local pcall = pcall

local is_resty_saml_init = false

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
        },
        idp_issuers = {
            type = "array",
            items = { type = "string" },
            description = "Accepted IdP issuers, unset accepts any, empty accepts none",
        },
        sp_acs_url = {
            type = "string",
            pattern = "^https?://",
            description = "Absolute external ACS URL, unset derives it from the request",
        },
        sp_audiences = {
            type = "array",
            items = { type = "string" },
            description = "Accepted assertion audiences, unset means sp_issuer",
        },
        clock_skew = {
            type = "number",
            minimum = 0,
            description = "Tolerated clock difference with the IdP in seconds, unset means 60",
        },
        replay_dict = {
            type = "string",
            minLength = 1,
            description = "lua_shared_dict name recording accepted assertions on this node",
        },
        replay_ttl = {
            type = "number",
            minimum = 1,
            description = "Seconds to record an assertion without expiry, unset means 600",
        },
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
        "secret",
    }
}

local plugin_name = "saml-auth"

local _M = {
    version = 0.1,
    priority = 2598,
    name = plugin_name,
    schema = schema,
}


function _M.check_schema(conf, _)
    return core.schema.check(schema, conf)
end


-- resty.saml keeps opts by reference, so it gets a copy of the plugin conf
local function new_saml(conf)
    local ok, saml = pcall(resty_saml.new, core.table.deepcopy(conf))
    if not ok then
        return nil, saml
    end
    return saml
end


function _M.rewrite(conf, ctx)
    if not is_resty_saml_init then
        local err = resty_saml.init({
            debug = false,
            data_dir = constants.apisix_lua_home .. "/deps/share/lua/5.1/resty/saml"
        })
        if err then
            core.log.error("saml init: ", err)
            return 503, {message = "saml init failed"}
        end
        is_resty_saml_init = true
    end

    local saml, err = core.lrucache.plugin_ctx(lrucache, ctx, nil, new_saml, conf)
    if not saml then
        core.log.error("saml new failed: ", err)
        return 500, {message = "create saml object failed"}
    end

    local data
    data, err = saml:authenticate()
    if err then
        core.log.error("saml authenticate failed: ", err)
        return 500, {message = "saml authentication failed"}
    end

    ctx.external_user = data
end

return _M
