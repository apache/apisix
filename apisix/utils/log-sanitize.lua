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

local pairs = pairs

local _M = {}


function _M.redact_params(params)
    local redacted = {
        method = params.method,
        scheme = params.scheme,
        host = params.host,
        port = params.port,
        path = params.path,
        ssl_server_name = params.ssl_server_name,
    }

    if params.headers then
        local safe_headers = {}
        for k, v in pairs(params.headers) do
            local lower_k = k:lower()
            if lower_k == "authorization" or lower_k == "x-api-key"
                or lower_k == "api-key" or lower_k == "cookie"
                or lower_k == "proxy-authorization" then
                safe_headers[k] = "[REDACTED]"
            else
                safe_headers[k] = v
            end
        end
        redacted.headers = safe_headers
    end

    return core.json.delay_encode(redacted, true)
end


function _M.redact_extra_opts(extra_opts)
    local redacted = core.table.deepcopy(extra_opts)
    redacted.auth = nil
    return core.json.delay_encode(redacted, true)
end


return _M
