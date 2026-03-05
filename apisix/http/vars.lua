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

local core              = require("apisix.core")
local ngx_re            = require("ngx.re")
local ngx               = ngx
local string            = string
local string_rep        = string.rep
local ngx_decode_base64 = ngx.decode_base64

local _M                = {
    version = 0.1,
}


local function get_bearer_token(ctx)
    local auth_header = core.request.header(ctx, "Authorization")
    if not auth_header then
        return nil
    end

    local parts = ngx_re.split(auth_header, " ", nil, nil, 2)
    if not parts or #parts < 2 then
        return nil
    end

    if string.lower(parts[1]) ~= "bearer" then
        return nil
    end

    return parts[2]
end


local function decode_jwt_payload(token)
    local parts = ngx_re.split(token, "\\.", nil, nil, 3)
    if not parts or #parts < 2 then
        return nil
    end

    local payload = parts[2]
    payload = payload:gsub("-", "+"):gsub("_", "/")
    local remainder = #payload % 4
    if remainder > 0 then
        payload = payload .. string_rep("=", 4 - remainder)
    end

    local payload_raw = ngx_decode_base64(payload)
    if not payload_raw then
        return nil
    end

    local decoded = core.json.decode(payload_raw)
    if not decoded or type(decoded) ~= "table" then
        return nil
    end

    return decoded
end


core.ctx.register_var("jwt_iss", function(ctx)
    local token = get_bearer_token(ctx)
    if not token then
        return nil
    end

    local payload = decode_jwt_payload(token)
    if not payload then
        return nil
    end

    if type(payload.iss) ~= "string" then
        return nil
    end

    return payload.iss
end)


return _M
