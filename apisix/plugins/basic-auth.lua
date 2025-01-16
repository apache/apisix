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
local consumer = require("apisix.consumer")
local schema_def = require("apisix.schema_def")
local auth_utils = require("apisix.utils.auth")

local lrucache = core.lrucache.new({
    ttl = 300, count = 512
})

local schema = {
    type = "object",
    title = "work with route or service object",
    properties = {
        hide_credentials = {
            type = "boolean",
            default = false,
        }
    },
    anonymous_consumer = schema_def.anonymous_consumer_schema,
}

local consumer_schema = {
    type = "object",
    title = "work with consumer object",
    properties = {
        username = { type = "string" },
        password = { type = "string" },
    },
    encrypt_fields = {"password"},
    required = {"username", "password"},
}

local plugin_name = "basic-auth"


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

    local function do_extract(auth)
        local obj = { username = "", password = "" }

        local m, err = ngx.re.match(auth, "Basic\\s(.+)", "jo")
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
        core.log.info("plugin access phase, authorization: ",
                      obj.username, ": ", obj.password)

        return obj, nil
    end

    local matcher, err = lrucache(authorization, nil, do_extract, authorization)

    if matcher then
        return matcher.username, matcher.password, err
    else
        return "", "", err
    end

end


local function find_consumer(ctx)
    local auth_header = core.request.header(ctx, "Authorization")
    if not auth_header then
        core.response.set_header("WWW-Authenticate", "Basic realm='.'")
        return nil, nil, "Missing authorization in request"
    end

    local username, password, err = extract_auth_header(auth_header)
    if err then
        if auth_utils.is_running_under_multi_auth(ctx) then
            return nil, nil, err
        end
        core.log.warn(err)
        return nil, nil, "Invalid authorization in request"
    end

    local cur_consumer, consumer_conf, err = consumer.find_consumer(plugin_name,
                                             "username", username)
    if not cur_consumer then
        err = "failed to find user: " .. (err or "invalid user")
        if auth_utils.is_running_under_multi_auth(ctx) then
            return nil, nil, err
        end
        core.log.warn(err)
        return nil, nil, "Invalid user authorization"
    end

    if cur_consumer.auth_conf.password ~= password then
        return nil, nil, "Invalid user authorization"
    end

    return cur_consumer, consumer_conf, err
end


function _M.rewrite(conf, ctx)
    core.log.info("plugin access phase, conf: ", core.json.delay_encode(conf))

    local cur_consumer, consumer_conf, err = find_consumer(ctx)
    if not cur_consumer then
        if not conf.anonymous_consumer then
            return 401, { message = err }
        end
        cur_consumer, consumer_conf, err = consumer.get_anonymous_consumer(conf.anonymous_consumer)
        if not cur_consumer then
            err = "basic-auth failed to authenticate the request, code: 401. error: " .. err
            core.log.error(err)
            return 401, { message = "Invalid user authorization" }
        end
    end

    core.log.info("consumer: ", core.json.delay_encode(cur_consumer))

    if conf.hide_credentials then
        core.request.set_header(ctx, "Authorization", nil)
    end

    consumer.attach_consumer(ctx, cur_consumer, consumer_conf)

    core.log.info("hit basic-auth access")
end

return _M
