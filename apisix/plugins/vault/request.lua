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

local http = require("resty.http")
local core = require("apisix.core")
local json = require("cjson")

local _M = {}

local function _vault_fetch (host_addr, path, method, vault_token)
    local httpc = http.new()
    local res, err = httpc:request_uri(host_addr, {
        method = method,
        path = path,
        headers = {
            ["X-Vault-Token"] = vault_token
        }
    })

    if not res or err then
        core.log.error("failed to fetch data from vault server running on: ", host_addr
                        " with error: ", err)
        return {}
    end

    local tab = json.decode(res.body)
    if not tab then
        return {}
    end

    return tab.data
end
_M.fetch = _vault_fetch

return _M
