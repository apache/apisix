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
local core         = require("apisix.core")
local http         = require("resty.http")
local google_oauth = require("apisix.utils.google-cloud-oauth")

local str_sub       = core.string.sub
local str_find      = core.string.find
local decode_base64 = ngx.decode_base64
 
local lrucache = core.lrucache.new({ ttl = 300, count= 8 })

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
                    type = "array",
                    default = {
                        "https://www.googleapis.com/auth/cloud-platform"
                    }
                },
                entries_uri = {
                    type = "string",
                    default = "https://secretmanager.googleapis.com/v1"
                },
            },
            required = { "client_email", "private_key", "project_id" }
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
}

local _M = {
    schema = schema
}

local function fetch_oauth_conf(conf)
    if conf.auth_config then
        return conf.auth_config
    end

    local file_content, err = core.io.get_file(conf.auth_file)
    if not file_content then
        return nil, "failed to read configuration, file: " .. conf.auth_file .. ", err: " .. err
    end

    local config_tab, err = core.json.decode(file_content)
    if not config_tab then
        return nil, "config parse failure, data: " .. file_content .. ", err: " .. err
    end

    local config = {
        auth_config = {
            client_email = config_tab.client_email,
            private_key = config_tab.private_key,
            project_id = config_tab.project_id
        }
    }

    local ok, err = core.schema.check(schema, config)
    if not ok then
        return nil, "config parse failure, file: " .. conf.auth_file .. ", err: " .. err
    end

    return config_tab
end


local function get_secret(oauth, secrets_id)
    local http_new = http.new()

    local access_token = oauth:generate_access_token()
    if not access_token then
        return nil, "failed to get google oauth token"
    end

    local entries_uri = oauth.entries_uri .. "/projects/" .. oauth.project_id
                            .. "/secrets/" .. secrets_id .. "/versions/latest:access"

    local res, err = http_new:request_uri(entries_uri, {
        ssl_verify = oauth.ssl_verify,
        method = "GET",
        headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = (oauth.access_token_type or "Bearer") .. " " .. access_token,
        },
    })

    if not res then
        return nil, err
    end

    if res.status ~= 200 then
        return nil, res.body
    end

    local body, err = core.json.decode(res.body)
    if not body then
        return nil, "failed to parse response data, " .. err
    end

    local payload = body.payload
    if not payload then
        return nil, "invalid payload"
    end

    return decode_base64(payload.data)
end


local function make_request_to_gcp(conf, secrets_id)
    local auth_config, err = fetch_oauth_conf(conf)
    if not auth_config then
        return nil, err
    end

    local lru_key =  auth_config.client_email .. "#" .. auth_config.project_id

    local oauth, err = lrucache(lru_key, "gcp", google_oauth.new, auth_config, conf.ssl_verify)
    if not oauth then
        return nil, "failed to create oauth object, " .. err
    end

    local secret, err = get_secret(oauth, secrets_id)
    if not secret then
        return nil, err
    end

    return secret
end


function _M.get(conf, key)
    core.log.info("fetching data from gcp for key: ", key)

    local idx = str_find(key, '/')

    local main_key = idx and str_sub(key, 1, idx - 1) or key
    if main_key == "" then
        return nil, "can't find main key, key: " .. key
    end

    local sub_key = idx and str_sub(key, idx + 1) or nil

    core.log.info("main: ", main_key, sub_key and ", sub: " .. sub_key or "")

    local res, err = make_request_to_gcp(conf, main_key)
    if not res then
        return nil, "failed to retrtive data from gcp secret manager: " .. err
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
