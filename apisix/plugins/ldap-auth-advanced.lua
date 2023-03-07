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

local core         = require("apisix.core")
local consumer_mod = require("apisix.consumer")
local ldap_cli     = require("resty.ldap.client")
local ldap_proto   = require("resty.ldap.protocol")

local pcall         = pcall
local ipairs        = ipairs
local str_find      = core.string.find
local str_format    = string.format
local decode_base64 = ngx.decode_base64
local ngx_re_match  = ngx.re.match
local ngx_re_gsub   = ngx.re.gsub
local ngx_re_split  = require("ngx.re").split

local LDAP_SEARCH_SCOPE_BASE_OBJECT = ldap_proto.SEARCH_SCOPE_BASE_OBJECT
local LDAP_SEARCH_DEREF_ALIASES_ALWAYS = ldap_proto.SEARCH_DEREF_ALIASES_ALWAYS

local auth_header_lrucache = core.lrucache.new({
    ttl = 300, count = 512
})

local schema = {
    type = "object",
    properties = {
        ldap_uri = { type = "string" },
        use_ldaps = {
            type = "boolean",
            default = false
        },
        use_starttls = {
            type = "boolean",
            default = false
        },
        ssl_verify = {
            type = "boolean",
            default = true,
        },
        timeout = {
            type = "integer",
            minimum = 1,
            maximum = 60000,
            default = 3000,
            description = "timeout in milliseconds",
        },
        keepalive = {type = "boolean", default = true},
        keepalive_timeout = {type = "integer", minimum = 1000, default = 60000},
        keepalive_pool_size = {type = "integer", minimum = 1, default = 5},
        keepalive_pool_name = {type = "string", default = nil},
        ldap_debug = {
            type = "boolean",
            default = false,
        },
        hide_credentials = {
            type = "boolean",
            default = false,
        },
        consumer_required = {
            type = "boolean",
            default = true,
        },
        user_dn_template = {
            type = "string",
        },
        user_membership_attribute = {
            type = "string",
            default = "memberOf",
        }
    },
    required = {"ldap_uri", "user_dn_template"}
}


local consumer_schema = {
    type = "object",
    properties = {
        user_dn = { type = "string" },
        group_dn = { type = "string" },
    },
    oneOf = {
        {required = {"user_dn"}},
        {required = {"group_dn"}},
    }
}

local plugin_name = "ldap-auth-advanced"

local _M = {
    version = 0.1,
    priority = 2540,
    type = "auth",
    name = plugin_name,
    schema = schema,
    consumer_schema = consumer_schema,
}


function _M.check_schema(conf, schema_type)
    if schema_type == core.schema.TYPE_CONSUMER then
        return core.schema.check(consumer_schema, conf)
    end

    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return ok, err
    end

    -- ensure %s in template
    if not str_find(conf.user_dn_template, "%s") or not ok then
        return false, "User DN template doesn't contain " ..
                        "the %s placeholder for the uid variable"
    end

    -- ensure only one %s in template
    if not pcall(str_format, conf.user_dn_template, "username") then
        return false, "User DN template has more than one " ..
                        "placeholder %s for the username variable."
    end

    if conf.use_starttls and conf.use_ldaps then
        return false, "STARTTLS and LDAPS cannot be open at the same time"
    end

    return true
end


local function extract_auth_header(authorization)
    local function do_extract(auth)
        local obj = { username = "", password = "" }

        local m, err = ngx_re_match(auth, "Basic\\s(.+)", "jo")
        if err then
            -- error authorization
            return nil, err
        end

        if not m then
            return nil, "Invalid authorization header format"
        end

        local decoded = decode_base64(m[1])

        if not decoded then
            return nil, "Failed to decode authentication header: " .. m[1]
        end

        local res
        res, err = ngx_re_split(decoded, ":")
        if err then
            return nil, "Split authorization err:" .. err
        end
        if #res < 2 then
            return nil, "Split authorization err: invalid decoded data: " .. decoded
        end

        obj.username = ngx_re_gsub(res[1], "\\s+", "", "jo")
        obj.password = ngx_re_gsub(res[2], "\\s+", "", "jo")

        return obj, nil
    end

    local matcher, err = auth_header_lrucache(authorization, nil, do_extract, authorization)

    if matcher then
        return matcher.username, matcher.password, err
    else
        return "", "", err
    end
end


function _M.rewrite(conf, ctx)
    -- extract userinfo from Authorization header
    local auth_header = core.request.header(ctx, "Authorization")
    if not auth_header then
        core.response.set_header("WWW-Authenticate", "Basic realm='.'")
        return 401, { message = "Missing authorization in request" }
    end

    local username, password, err = extract_auth_header(auth_header)
    if err then
        core.log.warn("extract auth header failed: ", err)
        return 401, { message = "Invalid authorization in request" }
    end
    core.log.info("plugin access phase, authorization: ",
                    username, ": ", password)

    if conf.hide_credentials then
        core.log.info("hide authorization header credentials")
        core.request.set_header(ctx, "Authorization", nil)
    end

    -- initialize LDAP connection
    local ldap_host, ldap_port = core.utils.parse_addr(conf.ldap_uri)
    local ldap_client = ldap_cli:new(ldap_host, ldap_port, {
        start_tls = conf.use_starttls,
        ldaps = conf.use_ldaps,
        ssl_verify = conf.ssl_verify,
        socket_timeout = conf.timeout,
        pool_name = conf.keepalive_pool_name,
        pool_size = conf.keepalive and conf.keepalive_pool_size or 0,
        keepalive_timeout = conf.keepalive_timeout,
    })

    -- perform authentication for user by simple_bind
    local user_dn = str_format(conf.user_dn_template, username)
    local res, err = ldap_client:simple_bind(user_dn, password)
    if not res then
        core.log.warn("ldap-auth-advanced failed: ", err)
        return 401, { message = "Invalid user authorization" }
    end

    -- stop if consumer attach mode is disabled
    if not conf.consumer_required then
        return
    end

    local res, err = ldap_client:search(
        user_dn,                          -- base_dn
        LDAP_SEARCH_SCOPE_BASE_OBJECT,    -- scope
        LDAP_SEARCH_DEREF_ALIASES_ALWAYS, -- deref_aliases
        0,                                -- size_limit
        0,                                -- time_limit
        false,                            -- types_only
        "(objectClass=*)",                -- filter: use default filter (objectClass=*)
        {conf.user_membership_attribute}  -- attributes
    )
    if not res then
        core.log.warn("ldap-auth-advanced failed: ", err)
        return 401, { message = "Failed to fetch user information" }
    end

    -- log search result for debug
    if conf.ldap_debug then
        core.log.info("ldap-auth-advanced user search result: ", core.json.encode(res))
    end

    -- get consumers with plugins turned on
    local consumer_conf = consumer_mod.plugin(plugin_name)
    if not consumer_conf then
        return 401, { message = "Missing related consumer" }
    end

    -- following codes does not use consumer_mod.consumers_kv because it
    -- does not support the ability to adaptively cull objects for which
    -- the specified key does not exist, and there is no need to use the
    -- secret manager to store data here (user_dn and group_dn are
    -- supposed to be accessible)
    local consumers_with_user_dn = {}
    local consumers_with_group_dn = {}
    for _, consumer in ipairs(consumer_conf.nodes) do
        local new_consumer = core.table.clone(consumer)

        -- user_dn and group_dn are mutually exclusive
        if new_consumer.auth_conf.user_dn then
            consumers_with_user_dn[new_consumer.auth_conf.user_dn] = new_consumer
        else
            consumers_with_group_dn[new_consumer.auth_conf.group_dn] = new_consumer
        end
    end

    -- perform user consumer attach firstly
    local consumer = consumers_with_user_dn[user_dn]
    if consumer then
        consumer_mod.attach_consumer(ctx, consumer, consumer_conf)
        return
    end

    -- perform group consumer attach
    local ldap_user = res[1] -- use user's own DN as the search base, so there is only one result
    local user_group_dns = ldap_user.attributes[conf.user_membership_attribute] or {}
    for _, group_dn in ipairs(user_group_dns) do
        local consumer = consumers_with_group_dn[group_dn]
        if consumer then
            consumer_mod.attach_consumer(ctx, consumer, consumer_conf)
            return
        end
    end

    if not ctx.consumer then
        return 401, { message = "Missing related consumer" }
    end
end


return _M
