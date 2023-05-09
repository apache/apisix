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

local cjson = require("cjson")
local http = require("resty.http")

local _M = {}


function _M.fetch_logs_from_loki(from, to, options)
    options = options or {}

    local direction = options.direction or "backward"
    local limit = options.limit or "10"
    local query = options.query or [[{job="apisix"} | json]]
    local url = options.url or "http://127.0.0.1:3100/loki/api/v1/query_range"
    local headers = options.headers or {
        ["X-Scope-OrgID"] = "tenant_1"
    }

    local httpc = http.new()
    local res, err = httpc:request_uri(url, {
        query = {
            start = from,
            ["end"] = to,
            direction = direction,
            limit = limit,
            query = query,
        },
        headers = headers
    })

    if not res or err then
        return nil, err
    end

    if res.status > 300 then
        return nil, "HTTP status code: " .. res.status .. ", body: " .. res.body
    end

    local data = cjson.decode(res.body)
    if not data then
        return nil, "failed to decode response body: " .. res.body
    end
    return data, nil
end


return _M
