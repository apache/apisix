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

-- Shared request/parse core for the embeddings drivers. Each provider differs
-- only in its request shape, auth header, and default endpoint; the HTTP call,
-- status check, and data[1].embedding extraction live here so a parsing fix
-- lands in one place.
local core    = require("apisix.core")
local type    = type

local HTTP_OK = ngx.HTTP_OK

local _M = {}

-- fetch(opts) where opts = { endpoint, headers, request, httpc, ssl_verify }
-- -> (vector_table, err)
function _M.fetch(opts)
    local payload, err = core.json.encode(opts.request)
    if not payload then
        return nil, "encode embeddings request: " .. (err or "")
    end

    local res
    res, err = opts.httpc:request_uri(opts.endpoint, {
        method = "POST",
        headers = opts.headers,
        body = payload,
        ssl_verify = opts.ssl_verify,
    })
    if not res or not res.body then
        return nil, "embeddings request failed: " .. (err or "")
    end
    if res.status ~= HTTP_OK then
        return nil, "embeddings endpoint returned " .. res.status
    end

    local decoded = core.json.decode(res.body)
    if not decoded or type(decoded.data) ~= "table" or type(decoded.data[1]) ~= "table"
       or type(decoded.data[1].embedding) ~= "table" then
        return nil, "malformed embeddings response"
    end
    return decoded.data[1].embedding
end

return _M
