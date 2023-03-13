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
local ngx = ngx
local ngx_re = require("ngx.re")
local consumer_mod = require("apisix.consumer")
local ok, ldap_cli = pcall(require, "resty.ldap.client")

local schema = {
    type = "object",
    title = "work with route or service object",
    properties = {
        base_dn = { type = "string" },
        ldap_uri = { type = "string" },
        use_tls = { type = "boolean", default = false },
        tls_verify = { type = "boolean", default = false },
        uid = { type = "string", default = "cn" }
    },
    required = {"base_dn","ldap_uri"},
}

local consumer_schema = {
    type = "object",
    title = "work with consumer object",
    properties = {
        user_dn = { type = "string" },
    },
    required = {"user_dn"},
}

local plugin_name = "ldap-auth"


local _M = {
    version = 0.1,
    priority = 2540,
    type = 'auth',
    name = plugin_name,
    schema = schema,
    consumer_schema = consumer_schema
}

function _M.check_schema(conf, schema_type)
    local ok, err
    if schema_type == core.schema.TYPE_CONSUMER then
        ok, err = core.schema.check(consumer_schema, conf)
    else
        ok, err = core.schema.check(schema, conf)
    end

    return ok, err
end

local function extract_auth_header(authorization)
    local obj = { username = "", password = "" }

    local m, err = ngx.re.match(authorization, "Basic\\s(.+)", "jo")
    if err then
        -- error authorization
        return nil, err
    end

    if not m then
        return nil, "Invalid authorization header format"
    end

    local decoded = ngx.decode_base64(m[1])

    if not decoded then
        return nil, "Failed to decode authentication header: " .. m[1]
    end

    local res
    res, err = ngx_re.split(decoded, ":")
    if err then
        return nil, "Split authorization err:" .. err
    end
    if #res < 2 then
        return nil, "Split authorization err: invalid decoded data: " .. decoded
    end

    obj.username = ngx.re.gsub(res[1], "\\s+", "", "jo")
    obj.password = ngx.re.gsub(res[2], "\\s+", "", "jo")

    return obj, nil
end

function _M.rewrite(conf, ctx)
    if not ok then -- ensure rasn library loaded
        core.log.error("failed to load lua-resty-ldap lib: ", ldap_cli)
        return 501
    end

    core.log.info("plugin rewrite phase, conf: ", core.json.delay_encode(conf))

    -- 1. extract authorization from header
    local auth_header = core.request.header(ctx, "Authorization")
    if not auth_header then
        core.response.set_header("WWW-Authenticate", "Basic realm='.'")
        return 401, { message = "Missing authorization in request" }
    end

    local user, err = extract_auth_header(auth_header)
    if err then
        core.log.warn(err)
        return 401, { message = "Invalid authorization in request" }
    end

    -- 2. try authenticate the user against the ldap server
    local ldap_host, ldap_port = core.utils.parse_addr(conf.ldap_uri)
    local ldap_client = ldap_cli:new(ldap_host, ldap_port, {
        start_tls = false,
        ldaps = conf.use_tls,
        ssl_verify = conf.tls_verify,
        socket_timeout = 10000,
        keepalive_pool_name = ldap_host .. ":" .. ldap_port .. "_ldapauth"
                                .. (conf.use_tls and "_tls" or ""),
        keepalive_pool_size = 5,
        keepalive_timeout = 60000,
    })

    local user_dn =  conf.uid .. "=" .. user.username .. "," .. conf.base_dn
    local res, err = ldap_client:simple_bind(user_dn, user.password)
    if not res then
        core.log.warn("ldap-auth failed: ", err)
        return 401, { message = "Invalid user authorization" }
    end

    -- 3. Retrieve consumer for authorization plugin
    local consumer_conf = consumer_mod.plugin(plugin_name)
    if not consumer_conf then
        return 401, { message = "Missing related consumer" }
    end

    local consumers = consumer_mod.consumers_kv(plugin_name, consumer_conf, "user_dn")
    local consumer = consumers[user_dn]
    if not consumer then
        return 401, {message = "Invalid user authorization"}
    end
    consumer_mod.attach_consumer(ctx, consumer, consumer_conf)

    core.log.info("hit basic-auth access")
end

return _M
