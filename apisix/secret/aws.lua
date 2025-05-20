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
require("resty.aws.config") -- to read env vars before initing aws module

local core = require("apisix.core")
local http = require("resty.http")
local aws = require("resty.aws")
local aws_instance

local sub = core.string.sub
local find = core.string.find
local env = core.env
local unpack = unpack

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
            default = "us-east-1",
        },
        endpoint_url = core.schema.uri_def,
    },
    required = {"access_key_id", "secret_access_key"},
}

local _M = {
    schema = schema
}

local function make_request_to_aws(conf, key)
    if not aws_instance then
        aws_instance = aws()
    end

    local region = conf.region

    local access_key_id = env.fetch_by_uri(conf.access_key_id) or conf.access_key_id

    local secret_access_key = env.fetch_by_uri(conf.secret_access_key) or conf.secret_access_key

    local session_token = env.fetch_by_uri(conf.session_token) or conf.session_token

    local credentials = aws_instance:Credentials({
        accessKeyId = access_key_id,
        secretAccessKey = secret_access_key,
        sessionToken = session_token,
    })

    local default_endpoint = "https://secretsmanager." .. region .. ".amazonaws.com"
    local scheme, host, port, _, _ = unpack(http:parse_uri(conf.endpoint_url or default_endpoint))
    local endpoint = scheme .. "://" .. host

    local sm = aws_instance:SecretsManager({
        credentials = credentials,
        endpoint = endpoint,
        region = region,
        port = port,
    })

    local res, err = sm:getSecretValue({
        SecretId = key,
        VersionStage = "AWSCURRENT",
    })

    if not res then
        return nil, err
    end

    if res.status ~= 200 then
        local data = core.json.encode(res.body)
        if data then
            return nil, "invalid status code " .. res.status .. ", " .. data
        end

        return nil, "invalid status code " .. res.status
    end

    return res.body.SecretString
end

-- key is the aws secretId
function _M.get(conf, key)
    core.log.info("fetching data from aws for key: ", key)

    local idx = find(key, '/')

    local main_key = idx and sub(key, 1, idx - 1) or key
    if main_key == "" then
        return nil, "can't find main key, key: " .. key
    end

    local sub_key = idx and sub(key, idx + 1) or nil

    core.log.info("main: ", main_key, sub_key and ", sub: " .. sub_key or "")

    local res, err = make_request_to_aws(conf, main_key)
    if not res then
        return nil, "failed to retrtive data from aws secret manager: " .. err
    end

    if not sub_key then
        return res
    end

    local data, err = core.json.decode(res)
    if not data then
        return nil, "failed to decode result, res: " .. res .. ", err: " .. err
    end

    return data[sub_key]
end


return _M
