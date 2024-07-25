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

--- GCP Tools.
local core       = require("apisix.core")
local http       = require("resty.http")
local google_oauth = require("apisix.plugins.google-cloud-logging.oauth")

local sub        = core.string.sub
local rfind_char = core.string.rfind_char
local type = type
local decode_base64 = ngx.decode_base64

local lrucache = core.lrucache.new({ttl = 300, count= 16})

local schema = {
    type = "object",
    properties = {
        auth_config = {
            type = "object",
            properties = {
                client_email = { type = "string" },
                private_key = { type = "string" },
                project_id = { type = "string" },
                token_uri = {
                    type = "string",
                    default = "https://oauth2.googleapis.com/token"
                },
                scopes = {
                    type = "string",
                    default = "https://www.googleapis.com/auth/cloud-platform"
                },
                entries_uri = {
                    type = "string",
                    default = "https://secretmanager.googleapis.com/v1/"
                },
            },
            required = { "client_email", "private_key", "project_id", "token_uri" }
        },
        ssl_verify = {
            type = "boolean",
            default = true
        },
        auth_file = { type = "string" },
    },
    oneOf = {
        { required = { "auth_config" } },
        { required = { "auth_file" } },
    },
    encrypt_fields = {"auth_config.private_key"},
}

local _M = {
    schema = schema
}

local function fetch_oauth_conf(conf)
    if conf.auth_config then
        return conf.auth_config
    end

    if not conf.auth_file then
        return nil, "configuration is not defined"
    end

    local file_content, err = core.io.get_file(conf.auth_file)
    if not file_content or err then
        return nil, "failed to read configuration, file: " .. conf.auth_file
    end

    local config_tab, err = core.json.decode(file_content)
    if not config_tab or err then
        return nil, "config parse failure, data: " .. file_content
    end

    if not config_tab.client_email or
       not config_tab.private_key or
       not config_tab.project_id or
       not config_tab.token_uri then
        return nil, "configuration is undefined, file: " .. conf.auth_file
    end

    return config_tab
end

local function create_oauth_object(auth_config, ssl_verify)
    return google_oauth:new(auth_config, ssl_verify)
end

local function get_secret(oauth, secrets_id)
    local http_new = http.new()

    local access_token = oauth:generate_access_token()
    if not access_token then
        return nil, "failed to get google oauth token"
    end

    local entries_uri
    if oauth.entries_uri == "http://127.0.0.1:1980/google/secret/" then
        entries_uri = oauth.entries_uri .. oauth.project_id .. "/" .. secrets_id

    else
        entries_uri = oauth.entries_uri .. "projects/" .. oauth.project_id
                            .. "/secrets/" .. secrets_id .. "/versions/latest:access"
    end

    local res, err = http_new:request_uri(entries_uri, {
        ssl_verify = oauth.ssl_verify,
        method = "GET",
        headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = (oauth.access_token_type or "Bearer") .. " " .. access_token,
        },
    })

    if not res or err then
        return nil, "invalid response"
    end

    if res.status ~= 200 then
        return nil, "invalid status code"
    end

    res, err = core.json.decode(res.body)
    if not res or err then
        return nil, "failed to parse response data"
    end

    local payload = res.payload
    if type(payload) ~= "table" then
        return nil, "invalid payload"
    end

    local secret_encoded = payload.data
    if type(secret_encoded) ~= "string" then
        return nil, "invalid secret string"
    end

    local secret = decode_base64(secret_encoded)
    return secret
end

local function make_request_to_gcp(conf, key)
    local auth_config, err = fetch_oauth_conf(conf)
    if not auth_config then
        return nil, err
    end

    local lru_key =  auth_config.client_email .. "#" .. auth_config.project_id

    local oauth, err = lrucache(lru_key, "gcp", create_oauth_object, auth_config, conf.ssl_verify)
    if not oauth or err then
        return nil, "failed to create oauth object"
    end

    local secret, err = get_secret(oauth, key)
    if not secret then
        return nil, err
    end

    return secret, nil
end

local function get(conf, key)
    core.log.info("fetching data from gcp for key: ", key)

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

    local res, err = make_request_to_gcp(conf, main_key)
    if not res then
        return nil, "failed to retrtive data from gcp secret manager: " .. err
    end

    local ret = core.json.decode(res)
    if not ret then
        return nil, "failed to decode result, res: " .. res
    end

    return ret[sub_key]
end

_M.get = get


return _M
