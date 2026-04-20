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

--- Authentication helpers for AI providers.
-- GCP OAuth2 token caching for Vertex AI and other Google Cloud providers.

local core = require("apisix.core")
local google_oauth = require("apisix.utils.google-cloud-oauth")
local lrucache = require("resty.lrucache")
local type = type
local os = os

local _M = {}

local gcp_access_token_cache = lrucache.new(1024 * 4)


--- Fetch (or retrieve from cache) a GCP OAuth2 access token.
-- @param ctx table Request context
-- @param name string Cache key name (driver instance name)
-- @param gcp_conf table GCP configuration (service_account_json, expire_early_secs, max_ttl)
-- @return string|nil Access token
-- @return string|nil Error message
function _M.fetch_gcp_access_token(ctx, name, gcp_conf)
    local key = core.lrucache.plugin_ctx_id(ctx, name)
    local access_token = gcp_access_token_cache:get(key)
    if not access_token then
        local auth_conf = {}
        gcp_conf = type(gcp_conf) == "table" and gcp_conf or {}
        local service_account_json = gcp_conf.service_account_json or
                                        os.getenv("GCP_SERVICE_ACCOUNT")
        if type(service_account_json) == "string" and service_account_json ~= "" then
            local conf, err = core.json.decode(service_account_json)
            if not conf then
                return nil, "invalid gcp service account json: " .. (err or "unknown error")
            end
            auth_conf = conf
        end
        local oauth = google_oauth.new(auth_conf)
        access_token = oauth:generate_access_token()
        if not access_token then
            return nil, "failed to get google oauth token"
        end
        local ttl = oauth.access_token_ttl or 3600
        if gcp_conf.expire_early_secs and ttl > gcp_conf.expire_early_secs then
            ttl = ttl - gcp_conf.expire_early_secs
        end
        if gcp_conf.max_ttl and ttl > gcp_conf.max_ttl then
            ttl = gcp_conf.max_ttl
        end
        gcp_access_token_cache:set(key, access_token, ttl)
        core.log.debug("set gcp access token in cache with ttl: ", ttl, ", key: ", key)
    end
    return access_token
end


return _M
