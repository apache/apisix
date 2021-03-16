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
local ipairs = ipairs
local consumer = require("apisix.consumer")

local lrucache = core.lrucache.new({
    ttl = 300, count = 512
})
local consumers_lrucache = core.lrucache.new({
    type = "plugin",
})

local schema = {
    type = "object",
    title = "work with route or service object",
    properties = {
        basedn = { type = "string" },
        ldapuri = { type = "string" },
        usetls = { type = "boolean" },
        uid = { type = "string" },
    },
    required = {"basedn","ldapuri"},
    additionalProperties = false,
}

local consumer_schema = {
    type = "object",
    title = "work with consumer object",
    properties = {
        userdn = { type = "string" },
    },
    required = {"userdn"},
    additionalProperties = false,
}

local plugin_name = "ldap-auth"

local _M = {
    version = 0.1,
    priority = 2520,
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

    if not ok then
        return false, err
    end

    return true
end

local function extract_auth_header(authorization)
    local obj = { username = "", password = "" }

    local m, err = ngx.re.match(auth, "Basic\\s(.+)", "jo")
    if err then
        -- error authorization
        return nil, err
    end

    local decoded = ngx.decode_base64(m[1])

    local res
    res, err = ngx_re.split(decoded, ":")
    if err then
        return nil, "split authorization err:" .. err
    end

    obj.username = ngx.re.gsub(res[1], "\\s+", "", "jo")
    obj.password = ngx.re.gsub(res[2], "\\s+", "", "jo")
    core.log.info("plugin access phase, authorization: ",
                  obj.username, ": ", obj.password)

    return obj, nil
end

function _M.rewrite(conf, ctx)
    core.log.info("plugin access phase, conf: ", core.json.delay_encode(conf))

    -- 1. extract authorization from header
    local auth_header = core.request.header(ctx, "Authorization")
    if not auth_header then
        core.response.set_header("WWW-Authenticate", "Basic realm='.'")
        return 401, { message = "Missing authorization in request" }
    end

    local username, password, err = extract_auth_header(auth_header)
    if err then
        return 401, { message = err }
    end

    -- 2. try authenticate the user against the ldap server
    local consumer_conf = consumer.plugin(plugin_name)
    if not consumer_conf then
        return 401, { message = "Missing related consumer" }
    end
    local uid = "cn"
    if conf.uid then 
        uid = conf.uid
    end
    local ld = assert (lualdap.open_simple (conf.ldapuri,
                uid+"="+username+","+conf.basedn,
                password))

    if not ld then
        return 401, { message = "Invalid user authorization" }
    end

    -- 3. Create temporary consumer for authorization plugin
    local consumer = {consumer_name = "", auth_conf = {username = ""}}
    consumer.consumer_name = username
    consumer.auth_conf.username = username

    consumer.attach_consumer(ctx, consumer, consumer_conf)

    core.log.info("hit basic-auth access")
end

return _M
