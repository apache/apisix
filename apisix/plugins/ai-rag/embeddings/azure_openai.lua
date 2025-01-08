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
local HTTP_INTERNAL_SERVER_ERROR = ngx.HTTP_INTERNAL_SERVER_ERROR
local HTTP_OK = ngx.HTTP_OK
local type = type

local _M = {}

_M.schema = {
    type = "object",
    properties = {
        endpoint = {
            type = "string",
        },
        api_key = {
            type = "string",
        },
    },
    required = { "endpoint", "api_key" }
}

function _M.get_embeddings(conf, body, httpc)
    local body_tab, err = core.json.encode(body)
    if not body_tab then
        return nil, HTTP_INTERNAL_SERVER_ERROR, err
    end

    local res, err = httpc:request_uri(conf.endpoint, {
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["api-key"] = conf.api_key,
        },
        body = body_tab
    })

    if not res or not res.body then
        return nil, HTTP_INTERNAL_SERVER_ERROR, err
    end

    if res.status ~= HTTP_OK then
        return nil, res.status, res.body
    end

    local res_tab, err = core.json.decode(res.body)
    if not res_tab then
        return nil, HTTP_INTERNAL_SERVER_ERROR, err
    end

    if type(res_tab.data) ~= "table" or core.table.isempty(res_tab.data) then
        return nil, HTTP_INTERNAL_SERVER_ERROR, res.body
    end

    local embeddings, err = core.json.encode(res_tab.data[1].embedding)
    if not embeddings then
        return nil, HTTP_INTERNAL_SERVER_ERROR, err
    end

    return res_tab.data[1].embedding
end


_M.request_schema = {
    type = "object",
    properties = {
        input = {
            type = "string"
        }
    },
    required = { "input" }
}

return _M
