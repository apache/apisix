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

--- AWS Tools.
local core = require("apisix.core")
local norm_path = require("pl.path").normpath
local http = require("resty.http")
local aws = require("resty.aws")

local sub = core.string.sub
local rfind_char = core.string.rfind_char
local env = core.env

--- AWS Environment Configuration
local AWS
local AWS_ACCESS_KEY_ID
local AWS_SECRET_ACCESS_KEY
local AWS_SESSION_TOKEN
local AWS_REGION

local schema = {
    type = "object",
    properties = {
        access_key_id = {
            type = "string",
        },
        secret_access_key = {
            type = "string",
        },
        session_token = {
            type = "string",
        },
        region = {
            type = "string",
        },
        endpoint_url = core.schema.uri_def,
    },
}

local _M = {
    schema = schema
}

local function initialize_aws()
    AWS_ACCESS_KEY_ID = env.fetch_by_uri("$ENV://AWS_ACCESS_KEY_ID")
    AWS_SECRET_ACCESS_KEY = env.fetch_by_uri("$ENV://AWS_SECRET_ACCESS_KEY")
    AWS_SESSION_TOKEN = env.fetch_by_uri("$ENV://AWS_SESSION_TOKEN")
    AWS_REGION = env.fetch_by_uri("$ENV://AWS_REGION")
    AWS = aws()
    initialize_aws= nil
end

local function make_request_to_aws(conf,key)
    if initialize_aws then
        initialize_aws()
    end

    local region = conf.region or AWS_REGION
    if not region then
        return nil, "aws secret manager requires region"
    end

    local access_key_id = env.fetch_by_uri(conf.access_key_id)
    if not access_key_id then
        access_key_id = conf.access_key_id or AWS_ACCESS_KEY_ID
    end

    local secret_access_key = env.fetch_by_uri(conf.secret_access_key)
    if not secret_access_key then
        secret_access_key = conf.secret_access_key or AWS_SECRET_ACCESS_KEY
    end

    local session_token = env.fetch_by_uri(conf.session_token)
    if not session_token then
        session_token = conf.session_token or AWS_SESSION_TOKEN
    end

    local my_creds = nil
    if access_key_id and secret_access_key then
        my_creds = AWS:Credentials {
            accessKeyId = access_key_id,
            secretAccessKey = secret_access_key,
            sessionToken = session_token,
        }
    end

    if not my_creds then
        return nil, "unable to retrieve secret from aws secret manager (invalid credentials)"
    end

    AWS.config.credentials = my_creds

    local pre, host, port, _, _ = unpack(http:parse_uri(conf.endpoint_url or "https://secretsmanager." .. region .. ".amazonaws.com"))
    local endpoint = pre .. "://" .. host

    local sm = AWS:SecretsManager {
        endpoint = endpoint,
        region = region,
        port = port,
    }

    local res, err = sm:getSecretValue {
        SecretId = key,
        VersionStage = "AWSCURRENT",
    }

    if type(res) ~= "table" then
        if err then
            return nil, "unable to retrieve secret from aws secret manager " .. err
        end
        return nil, "unable to retrieve secret from aws secret manager (invalid response)"
    end

    if res.status ~= 200 then
        local body = res.body
        if type(body) == "table" then
            err = core.json.decode(body)
        end

        if err then
            return nil, "failed to retrieve secret from aws secret manager " .. err
        end

        return nil, "failed to retrieve secret from aws secret manager (invalid status code received)"
    end

    local body = res.body
    if type(body) ~= "table" then
        return nil, "unable to retrieve secret from aws secret manager (invalid response)"
    end

    local secret = res.body.SecretString
    if type(secret) ~= "string" then
        return nil, "unable to retrieve secret from aws secret manager (invalid secret string)"
    end

    return secret
end

-- key is the aws secretId
local function get(conf,key)
    core.log.info("fetching data from aws for key: ", key)

    local idx = rfind_char(key, '/')
    if not idx then
        return nil, "error key format, key: " .. key
    end

    local main_key = sub(key, 1, idx - 1)
    if main_key == "" then
        return nil, "can't find main key, key: " .. key
    end

    local sub_key = sub(key, idx + 1)
    if sub_key == "" then
        return nil, "can't find sub key, key: " .. key
    end

    core.log.info("main: ", main_key, " sub: ", sub_key)

    local res,err = make_request_to_aws(conf,main_key)
    if not res then
        return nil, "failed to retrtive data from aws: " .. err
    end

    local ret = core.json.decode(res)
    if not ret then
        return nil, "failed to decode result, res: " .. res
    end

    return ret[sub_key]
end

_M.get = get


return _M
