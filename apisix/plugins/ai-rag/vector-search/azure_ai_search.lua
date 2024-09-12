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
local internal_server_error = ngx.HTTP_INTERNAL_SERVER_ERROR

local _M = {}


function _M.search(conf, search_body, httpc)
    local body = {
        vectorQueries = {
            {
                kind = "vector",
                vector = search_body.embeddings,
                fields = search_body.fields
            }
        }
    }
    local final_body = core.json.encode(body)
    local res, err = httpc:request_uri(conf.endpoint, {
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["api-key"] = conf.api_key,
        },
        body = final_body
    })

    if not res or not res.body then
        return nil, internal_server_error, err
    end

    if res.status ~= 200 then
        return nil, res.status, res.body
    end

    return res.body
end


_M.request_schema = {
    type = "object",
    properties = {
        fields = {
            type = "string"
        }
    },
    required = { "fields" }
}

return _M
