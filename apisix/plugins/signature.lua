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
local core     = require("apisix.core")
local redis_new = require("resty.redis").new
local ngx      = ngx
local md5      = ngx.md5
local encode_args = ngx.encode_args
local tonumber = tonumber
local plugin_name = "signature"

local schema = {
    type = "object",
    properties = {
        appkey = {type = "string",minLength = 5,maxLength = 32,pattern = [[^[a-zA-Z0-9_-]{5,32}$]]},
        secret = {type = "string",minLength = 1},
        algorithm = {
            type = "string",
            enum = {"md5"},
            default = "md5"
        },
        timeout = {type = "integer", minimum = 10, default = 10},
        anti_reply = {
            type = "boolean",
            default = true
        },
        policy = {
            type = "string",
            enum = {"redis"},
            default = "redis"
        },
        redis_host = {
            type = "string", minLength = 2, default = "127.0.0.1"
        },
        redis_port = {
            type = "integer", minimum = 1, default = 6379
        },
        redis_password = {
            type = "string", minLength = 0, default=""
        },
        redis_timeout = {
            type = "integer", minimum = 1
        },
        redis_keepalive = {
            type = "integer", minimum = 10
        },
        redis_poolsize = {
            type = "integer", minimum = 100
        },
    },
    required = {"appkey", "secret", "timeout", "algorithm"}
}

local _M = {
    version = 0.1,
    priority = 2513,
    type = 'auth',
    name = plugin_name,
    schema = schema,
}

function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    if not conf.algorithm then
        conf.algorithm = "md5"
    end

    if not conf.timeout then
        conf.timeout = 10
    end

    if conf.policy == "redis" then
        if not conf.redis_host then
            return false, "missing valid redis option host"
        end

        conf.redis_port = conf.redis_port or 6379
        conf.redis_timeout = conf.redis_timeout or 1000
    end

    return true
end

local function get_args(action)
    local query_params = ngx.req.get_uri_args()
    local encode_query = encode_args(query_params)
    local body = ""
    if action ~= "GET" then
        ngx.req.read_body()
        body = ngx.req.get_body_data()
        if "nil" == type(body) then
            body = ""
        end
    end

    local args = encode_query .. body
    core.log.info("request original args is: ",args)
    return args
end

local function anti_reply(conf,key)
    local is_attack = false
    local red = redis_new()
    local timeout = conf.redis_timeout or 1000    -- 1sec
    red:set_timeouts(timeout, timeout, timeout)

    local ok, err = red:connect(conf.redis_host, conf.redis_port or 6379)
    if not ok then
        core.log.error("failed to connect: ",err)
        return is_attack
    end

    local count
    count, err = red:get_reused_times()
    core.log.info("reused times: ",count)
    if 0 == count then
        if conf.redis_password and conf.redis_password ~= '' then
            local ok, err = red:auth(conf.redis_password)
            if not ok then
                core.log.error("authentication failed: ",err)
                return is_attack
            end
        end
    elseif err then
        core.log.info("get_reused_times err: ", err)
        return is_attack
    end

    key = "sign:" .. tostring(key)
    local ret,err = red:get(key)
    core.log.info("sign key: ", key," result: ",ret, " err: ",err)
    if ret == ngx.null then
        core.log.info("key does not exist: ", key)
        red:setex(key,conf.timeout,"")
    else
        is_attack = true
    end

    red:set_keepalive(conf.redis_keepalive * 1000, conf.redis_poolsize)

    return is_attack
end


function _M.rewrite(conf, ctx)
    -- read nonce
    local nonce = core.request.header(ctx,"nonce")
    if "nil" == type(nonce) then
        return 400, {message = "invalid nonce"}
    end
    core.log.info("nonce is:",nonce, " conf is: ",core.json.delay_encode(conf))

    -- check reply request
    if conf.anti_reply then
        local attack = anti_reply(conf,nonce)
        if attack then
            return 400, {message = "repeat request"}
        end
    end

    -- get request args, include query and body
    local args = get_args(ctx.var.request_method)

    -- check appkey
    local appkey = core.request.header(ctx, "appkey")
    if conf.appkey ~= appkey then
        return 400, {message = "app doesn't exist or banned"}
    end

    -- check request timeout
    local ts = core.request.header(ctx,"timestamp")
    local timestamp = tonumber(ts)
    if "nil" == type(timestamp) then
        return 400, {message = "invalid timestamp"}
    end

    local now = ngx.time()
    if math.abs(now - timestamp) > conf.timeout then
        core.log.info("request timeout, current time is ", now," ,request time is ",timestamp," timeout conf is ",conf.timeout)
        return 400, {message = "request timeout"}
    end

    -- check signature
    local unsign_text = args .. conf.secret .. ts .. nonce
    core.log.info("unsign text is: ", unsign_text)
    local calculate_sign = md5(unsign_text)
    local request_sign = core.request.header(ctx,"sign")
    if request_sign ~= calculate_sign then
        core.log.info("check sign fail, request sign is ", request_sign," ,calculate sign is ",calculate_sign)
        return 400, {message = "invalid request, wrong signature"}
    end

    core.log.info("hit signature authorization rewrite")
end

return _M

