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
local jwt = require("resty.jwt")

local ngx_time = ngx.time
local ngx_decode_base64 = ngx.decode_base64
local pcall = pcall


local _M = {}


local function get_secret(conf)
    local secret = conf.secret

    if conf.base64_secret then
        return ngx_decode_base64(secret)
    end

    return secret
end

local function get_real_payload(key, exp, payload)
    local real_payload = {
        key = key,
        exp = ngx_time() + exp
    }
    if payload then
        local extra_payload = core.json.decode(payload)
        core.table.merge(extra_payload, real_payload)
        return extra_payload
    end
    return real_payload
end

local function sign_jwt_with_HS(key, auth_conf, payload)
    local auth_secret, err = get_secret(auth_conf)
    if not auth_secret then
        core.log.error("failed to sign jwt, err: ", err)
        return nil, "failed to sign jwt: failed to get auth_secret"
    end
    local ok, jwt_token = pcall(jwt.sign, _M,
            auth_secret,
            {
                header = {
                    typ = "JWT",
                    alg = auth_conf.algorithm
                },
                payload = get_real_payload(key, auth_conf.exp, payload)
            }
    )
    if not ok then
        core.log.error("failed to sign jwt, err: ", jwt_token.reason)
        return nil, "failed to sign jwt"
    end
    return jwt_token
end

local function sign_jwt_with_RS256_ES256(key, auth_conf, payload)
    local ok, jwt_token = pcall(jwt.sign, _M,
            auth_conf.private_key,
            {
                header = {
                    typ = "JWT",
                    alg = auth_conf.algorithm,
                    x5c = {
                        auth_conf.public_key,
                    }
                },
                payload = get_real_payload(key, auth_conf.exp, payload)
            }
    )
    if not ok then
        core.log.error("failed to sign jwt, err: ", jwt_token.reason)
        return nil, "failed to sign jwt"
    end
    return jwt_token
end

local function get_sign_handler(algorithm)
    if not algorithm or algorithm == "HS256" or algorithm == "HS512" then
        return sign_jwt_with_HS
    elseif algorithm == "RS256" or algorithm == "ES256" then
        return sign_jwt_with_RS256_ES256
    end
end

local function gen_token(auth_conf, payload)
    if not auth_conf.exp then
        auth_conf.exp = 86400
    end
    if not auth_conf.lifetime_grace_period then
        auth_conf.lifetime_grace_period = 0
    end
    if not auth_conf.algorithm then
        auth_conf.algorithm = "HS256"
    end
    local sign_handler = get_sign_handler(auth_conf.algorithm)
    local jwt_token, err = sign_handler(auth_conf.key, auth_conf, payload)
    return jwt_token, err
end


_M.gen_token = gen_token

return _M
