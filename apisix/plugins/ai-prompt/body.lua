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
local ngx = ngx
local pairs = pairs
local type = type

local _M = {}


function _M.read(max_size)
    local body, err = core.request.get_json_request_body_table(max_size)
    if body then
        return body
    end

    local message = type(err) == "table" and err.message or err
    if type(message) == "string"
       and core.string.find(message, "greater than the maximum size", 1, true) then
        return nil, 413, err
    end

    return nil, 400, err
end


function _M.replace(target, replacement)
    for key in pairs(target) do
        target[key] = nil
    end
    for key, value in pairs(replacement) do
        target[key] = value
    end
end


function _M.write(ctx, body)
    local encoded, err = core.json.encode(body)
    if not encoded then
        return 500, {message = "failed to encode modified JSON request body: " .. err}
    end

    ngx.req.set_body_data(encoded)
    ctx.ai_request_body_changed = true
end


return _M
