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

--- Vault Tools.
--  Vault is an identity-based secrets and encryption management system.

local core       = require("apisix.core")
local http       = require("resty.http")

local norm_path = require("pl.path").normpath

local sub        = core.string.sub
local rfind_char = core.string.rfind_char
local env        = core.env

local schema = {
    type = "object",
    properties = {
        uri = core.schema.uri_def,
        prefix = {
            type = "string",
        },
        token = {
            type = "string",
        },
    },
    required = {"uri", "prefix", "token"},
}

local _M = {
    schema = schema
}

local function make_request_to_vault(conf, method, key, data)
    local httpc = http.new()
    -- config timeout or default to 5000 ms
    httpc:set_timeout((conf.timeout or 5)*1000)

    local req_addr = conf.uri .. norm_path("/v1/"
                .. conf.prefix .. "/" .. key)

    local token, _ = env.fetch_by_uri(conf.token)
    if not token then
        token = conf.token
    end

    local res, err = httpc:request_uri(req_addr, {
        method = method,
        headers = {
            ["X-Vault-Token"] = token
        },
        body = core.json.encode(data or {}, true)
    })

    if not res then
        return nil, err
    end

    return res.body
end

-- key is the vault kv engine path
local function get(conf, key)
    core.log.info("fetching data from vault for key: ", key)

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

    local res, err = make_request_to_vault(conf, "GET", main_key)
    if not res then
        return nil, "failed to retrtive data from vault kv engine: " .. err
    end

    local ret = core.json.decode(res)
    if not ret or not ret.data then
        return nil, "failed to decode result, res: " .. res
    end

    return ret.data[sub_key]
end

_M.get = get


return _M
