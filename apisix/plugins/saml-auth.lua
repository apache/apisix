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
    },
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

function _M.check_schema(conf, schema_type)
    return core.schema.check(schema, conf)
end

local function create_saml_obj(conf)
    return resty_saml.new(conf)
end

function _M.rewrite(conf, ctx)
    if not is_resty_saml_init then
        local err = resty_saml.init({
            debug = true,
            data_dir = constants.saml_data_dir,
        })
        if err then
            core.log.error("saml init: ", err)
            return 503
        end
        is_resty_saml_init = true
    end

    core.log.info("plugin rewrite phase, conf: ", core.json.delay_encode(conf))

    local saml = core.lrucache.plugin_ctx(lrucache, ctx, nil, create_saml_obj, conf)

    local data = saml:authenticate()

    core.log.info("saml auth success: ", core.json.delay_encode(data))
end

return _M
