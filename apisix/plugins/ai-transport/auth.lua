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
local tostring = tostring
local ngx_md5 = ngx.md5

local _M = {}

local gcp_access_token_cache = lrucache.new(1024 * 4)


--- Fetch (or retrieve from cache) a GCP OAuth2 access token.
--
-- Keyed on the credentials themselves rather than on the request ctx: the token
-- depends only on the service account, so identical credentials share one token
-- across routes, and callers need no ctx to ask for one.
-- @param name string Cache key name (driver instance name)
-- @param gcp_conf table GCP configuration (service_account_json, expire_early_secs, max_ttl)
-- @return string|nil Access token
-- @return string|nil Error message
function _M.fetch_gcp_access_token(name, gcp_conf)
    -- The credentials may arrive as a secret ref resolved per request, so key on
    -- the resolved value; hash it so the cache never holds the raw JSON. Include
    -- the fields that change how long the token is cached (expire_early_secs,
    -- max_ttl) so that identical credentials under different TTL policies do not
    -- share an entry, and use a 128-bit digest instead of a 32-bit CRC so that
    -- distinct credentials cannot collide onto the wrong cached token.
    local conf = type(gcp_conf) == "table" and gcp_conf or {}
    local sa = conf.service_account_json or os.getenv("GCP_SERVICE_ACCOUNT")
    local key = ngx_md5((sa or "") .. "\0"
                        .. tostring(conf.expire_early_secs or "") .. "\0"
                        .. tostring(conf.max_ttl or "")) .. "#" .. (name or "")
    local access_token = gcp_access_token_cache:get(key)
    if not access_token then
        local auth_conf = {}
        if type(sa) == "string" and sa ~= "" then
            local decoded, err = core.json.decode(sa)
            if not decoded then
                return nil, "invalid gcp service account json: " .. (err or "unknown error")
            end
            auth_conf = decoded
        end
        local oauth = google_oauth.new(auth_conf)
        access_token = oauth:generate_access_token()
        if not access_token then
            return nil, "failed to get google oauth token"
        end
        local ttl = oauth.access_token_ttl or 3600
        if conf.expire_early_secs and ttl > conf.expire_early_secs then
            ttl = ttl - conf.expire_early_secs
        end
        if conf.max_ttl and ttl > conf.max_ttl then
            ttl = conf.max_ttl
        end
        gcp_access_token_cache:set(key, access_token, ttl)
        core.log.debug("set gcp access token in cache with ttl: ", ttl, ", key: ", key)
    end
    return access_token
end


return _M
