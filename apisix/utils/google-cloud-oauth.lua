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
local type = type
local setmetatable = setmetatable

local ngx_update_time = ngx.update_time
local ngx_time = ngx.time
local ngx_encode_args = ngx.encode_args

local http = require("resty.http")
local jwt = require("resty.jwt")


local function get_timestamp()
    ngx_update_time()
    return ngx_time()
end


local _M = {}


function _M:generate_access_token()
    if not self.access_token or get_timestamp() > self.access_token_expire_time - 60 then
        self:refresh_access_token()
    end
    return self.access_token
end


function _M:refresh_access_token()
    local http_new = http.new()
    local res, err = http_new:request_uri(self.token_uri, {
        ssl_verify = self.ssl_verify,
        method = "POST",
        body = ngx_encode_args({
            grant_type = "urn:ietf:params:oauth:grant-type:jwt-bearer",
            assertion = self:generate_jwt_token()
        }),
        headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
        },
    })

    if not res then
        core.log.error("failed to refresh google oauth access token, ", err)
        return
    end

    if res.status ~= 200 then
        core.log.error("failed to refresh google oauth access token: ", res.body)
        return
    end

    res, err = core.json.decode(res.body)
    if not res then
        core.log.error("failed to parse google oauth response data: ", err)
        return
    end

    self.access_token = res.access_token
    self.access_token_type = res.token_type
    self.access_token_expire_time = get_timestamp() + res.expires_in
end


function _M:generate_jwt_token()
    local payload = core.json.encode({
        iss = self.client_email,
        aud = self.token_uri,
        scope = self.scope,
        iat = get_timestamp(),
        exp = get_timestamp() + (60 * 60)
    })

    local jwt_token = jwt:sign(self.private_key, {
        header = { alg = "RS256", typ = "JWT" },
        payload = payload,
    })

    return jwt_token
end


function _M:new(config, ssl_verify)
    local oauth = {
        client_email = config.client_email,
        private_key = config.private_key,
        project_id = config.project_id,
        token_uri = config.token_uri or "https://oauth2.googleapis.com/token",
        auth_uri = config.auth_uri or "https://accounts.google.com/o/oauth2/auth",
        entries_uri = config.entries_uri or "https://logging.googleapis.com/v2/entries:write",
        access_token = nil,
        access_token_type = nil,
        access_token_expire_time = 0,
    }

    oauth.ssl_verify = ssl_verify

    if config.scopes then
        if type(config.scopes) == "string" then
            oauth.scope = config.scopes
        end

        if type(config.scopes) == "table" then
            oauth.scope = core.table.concat(config.scopes, " ")
        end
    else
        -- https://developers.google.com/identity/protocols/oauth2/scopes#logging
        oauth.scope = core.table.concat({ "https://www.googleapis.com/auth/logging.read",
                                          "https://www.googleapis.com/auth/logging.write",
                                          "https://www.googleapis.com/auth/logging.admin",
                                          "https://www.googleapis.com/auth/cloud-platform" }, " ")
    end

    setmetatable(oauth, { __index = self })
    return oauth
end


return _M
