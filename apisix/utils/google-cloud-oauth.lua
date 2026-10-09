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
local os_getenv = os.getenv

local ngx_update_time = ngx.update_time
local ngx_time = ngx.time
local ngx_encode_args = ngx.encode_args

local http = require("resty.http")
local jwt = require("resty.jwt")


-- Metadata server endpoint used by Application Default Credentials / GKE
-- Workload Identity to obtain an access token for the attached service account.
-- The host can be overridden with the standard GCE_METADATA_HOST env var (host
-- only, e.g. "metadata.google.internal" or "127.0.0.1:8080") or the
-- `metadata_host` config field (full base URL, mainly for testing).
local DEFAULT_METADATA_HOST = "http://metadata.google.internal"
local METADATA_TOKEN_PATH = "/computeMetadata/v1/instance/service-accounts/default/token"


local function get_timestamp()
    ngx_update_time()
    return ngx_time()
end


local _M = {}


function _M.generate_access_token(self)
    if not self.access_token or get_timestamp() > self.access_token_expire_time - 60 then
        self:refresh_access_token()
    end
    return self.access_token
end


local function set_access_token(self, res)
    self.access_token = res.access_token
    self.access_token_type = res.token_type
    self.access_token_ttl = res.expires_in
    self.access_token_expire_time = get_timestamp() + res.expires_in
end


-- Fetch an access token from the GCE/GKE metadata server. This is how
-- Application Default Credentials / Workload Identity authenticate: the token
-- is minted by the platform for the service account attached to the workload,
-- so no static service account key is required.
function _M.refresh_access_token_from_metadata_server(self)
    local http_new = http.new()
    local res, err = http_new:request_uri(self.metadata_host .. METADATA_TOKEN_PATH, {
        method = "GET",
        headers = {
            ["Metadata-Flavor"] = "Google",
        },
    })

    if not res then
        core.log.error("failed to fetch google access token from metadata server, ", err)
        return
    end

    if res.status ~= 200 then
        core.log.error("failed to fetch google access token from metadata server: ", res.body)
        return
    end

    res, err = core.json.decode(res.body)
    if not res then
        core.log.error("failed to parse google metadata server response data: ", err)
        return
    end

    set_access_token(self, res)
end


function _M.refresh_access_token(self)
    if self.use_metadata_server then
        return self:refresh_access_token_from_metadata_server()
    end

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

    set_access_token(self, res)
end


function _M.generate_jwt_token(self)
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


function _M.new(config, ssl_verify)
    local metadata_host = config.metadata_host or os_getenv("GCE_METADATA_HOST")
    if metadata_host and not core.string.has_prefix(metadata_host, "http") then
        metadata_host = "http://" .. metadata_host
    end

    local oauth = {
        client_email = config.client_email,
        private_key = config.private_key,
        project_id = config.project_id,
        token_uri = config.token_uri or "https://oauth2.googleapis.com/token",
        auth_uri = config.auth_uri or "https://accounts.google.com/o/oauth2/auth",
        entries_uri = config.entries_uri,
        metadata_host = metadata_host or DEFAULT_METADATA_HOST,
        access_token = nil,
        access_token_type = nil,
        access_token_expire_time = 0,
    }

    -- Use the metadata server (ADC / Workload Identity) when explicitly requested
    -- or when no service account private key is available. This lets APISIX run
    -- keyless on GKE with Workload Identity instead of mounting a static SA key.
    oauth.use_metadata_server = config.use_metadata_server or (config.private_key == nil)

    oauth.ssl_verify = ssl_verify

    if config.scope then
        if type(config.scope) == "string" then
            oauth.scope = config.scope
        end

        if type(config.scope) == "table" then
            oauth.scope = core.table.concat(config.scope, " ")
        end
    else
        oauth.scope = "https://www.googleapis.com/auth/cloud-platform"
    end

    return setmetatable(oauth, { __index = _M })
end


return _M
