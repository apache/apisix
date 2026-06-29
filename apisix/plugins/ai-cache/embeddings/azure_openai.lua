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

local _M = {}

_M.schema = {
    type = "object",
    properties = {
        endpoint = { type = "string" },
        api_key = { type = "string" },
        dimensions = { type = "integer", minimum = 1 },
    },
    required = { "endpoint", "api_key" },
}

-- get_embeddings(conf, text, httpc, ssl_verify) -> (vector_table, err)
function _M.get_embeddings(conf, text, httpc, ssl_verify)
    local req = { input = text }
    if conf.dimensions then
        req.dimensions = conf.dimensions
    end
    local payload, err = core.json.encode(req)
    if not payload then
        return nil, "encode embeddings request: " .. (err or "")
    end

    local res
    res, err = httpc:request_uri(conf.endpoint, {
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["api-key"] = conf.api_key,
        },
        body = payload,
        ssl_verify = ssl_verify,
    })
    if not res then
        return nil, "embeddings request failed: " .. (err or "")
    end
    if res.status ~= 200 then
        return nil, "embeddings endpoint returned " .. res.status
    end

    local decoded
    decoded, err = core.json.decode(res.body)
    if not decoded or type(decoded.data) ~= "table" or type(decoded.data[1]) ~= "table"
       or type(decoded.data[1].embedding) ~= "table" then
        return nil, "malformed embeddings response"
    end
    return decoded.data[1].embedding
end

return _M
