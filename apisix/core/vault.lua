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
local http = require("resty.http")
local json = require("cjson")

local fetch_local_conf = require("apisix.core.config_local").local_conf
local norm_path = require("pl.path").normpath

local _M = {}

local function fetch_vault_conf()
    local conf, err = fetch_local_conf()
    if not conf then
        return nil, "failed to fetch vault configuration from config yaml: " .. err
    end

    if not conf.vault then
        return nil, "accessing vault data requires configuration information"
    end
    return conf.vault
end


local function make_request_to_vault(method, key, skip_prefix, data)
    local vault, err = fetch_vault_conf()
    if not vault then
        return nil, err
    end

    local httpc = http.new()
    -- config timeout or default to 5000 ms
    httpc:set_timeout((vault.timeout or 5)*1000)

    local req_addr = vault.host
    if not skip_prefix then
        req_addr = req_addr .. norm_path("/v1/"
                .. vault.prefix .. "/" .. key)
    else
        req_addr = req_addr .. norm_path("/v1/" .. key)
    end

    local res, err = httpc:request_uri(req_addr, {
        method = method,
        headers = {
            ["X-Vault-Token"] = vault.token
        },
        body = core.json.encode(data or  {}, true)
    })
    if not res then
        return nil, err
    end

    return res.body
end

-- key is the vault kv engine path, joined with config yaml vault prefix.
-- It takes an extra optional boolean param skip_prefix. If enabled, it simply doesn't use the
-- prefix defined inside config yaml under vault config for fetching data.
local function get(key, skip_prefix)
    core.log.info("fetching data from vault for key: ", key)

    local res, err = make_request_to_vault("GET", key, skip_prefix)
    if not res then
        return nil, "failed to retrtive data from vault kv engine " .. err
    end

    return json.decode(res)
end

_M.get = get

-- key is the vault kv engine path, data is json key value pair.
-- It takes an extra optional boolean param skip_prefix. If enabled, it simply doesn't use the
-- prefix defined inside config yaml under vault config for storing data.
local function set(key, data, skip_prefix)
    core.log.info("storing data into vault for key: ", key,
                    "and value: ", core.json.delay_encode(data, true))

    local res, err = make_request_to_vault("POST", key, skip_prefix, data)
    if not res then
        return nil, "failed to store data into vault kv engine " .. err
    end

    return true
end
_M.set = set


-- key is the vault kv engine path, joined with config yaml vault prefix.
-- It takes an extra optional boolean param skip_prefix. If enabled, it simply doesn't use the
-- prefix defined inside config yaml under vault config for deleting data.
local function delete(key, skip_prefix)
    core.log.info("deleting data from vault for key: ", key)

    local res, err = make_request_to_vault("DELETE", key, skip_prefix)

    if not res then
        return nil, "failed to delete data into vault kv engine " .. err
    end

    return true
end

_M.delete = delete

return _M
