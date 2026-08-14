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
local r_jwt = require "resty.jwt"
local test_admin = require "lib.test_admin"

local _M = {}

-- Sentinel: set a defaulted claim to _M.OMIT to drop it from the payload.
_M.OMIT = {}

local BCL_EVENT = "http://schemas.openid.net/event/backchannel-logout"

-- Signs an RS256 back-channel logout token against t/certs/private.pem.
-- Defaults are filled for iss/aud/iat/exp/events; pass a claim to override,
-- or _M.OMIT to drop a defaulted claim. jti and sid/sub are NOT defaulted --
-- pass whatever the test needs (omit by simply not passing).
function _M.sign(claims)
    local payload = {
        iss = "http://127.0.0.1:6724",
        aud = "bcl-client",
        iat = ngx.time(),
        exp = ngx.time() + 120,
        events = { [BCL_EVENT] = {} },
    }
    for k, v in pairs(claims or {}) do
        payload[k] = v
    end
    for k, v in pairs(payload) do
        if v == _M.OMIT then
            payload[k] = nil
        end
    end
    return r_jwt:sign(test_admin.read_file("t/certs/private.pem"), {
        header = { typ = "JWT", alg = "RS256", kid = "bclkey" },
        payload = payload,
    })
end

return _M
