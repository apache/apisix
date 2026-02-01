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
local http = require("resty.http")

local HTTP_INTERNAL_SERVER_ERROR = ngx.HTTP_INTERNAL_SERVER_ERROR
local HTTP_OK = ngx.HTTP_OK

local _M = {}

_M.schema = {
    type = "object",
    properties = {
        endpoint = {
            type = "string",
            description = "The endpoint for the OpenAI embeddings API."
        },
        api_key = {
            type = "string",
            description = "The API key for authentication."
        },
        model = {
            type = "string",
            default = "text-embedding-3-large",
            description = "The model to use for generating embeddings."
        },
        dimensions = {
            type = "integer",
            minimum = 1,
            description = "The number of dimensions for the embeddings."
        }
    },
    required = { "endpoint", "api_key" }
}

local function request_embedding_vector(endpoint, headers, body_tab)
    local body_str, err = core.json.encode(body_tab)
    if not body_str then
        return nil, HTTP_INTERNAL_SERVER_ERROR, err
    end

    local httpc = http.new()
    local res, err = httpc:request_uri(endpoint, {
        method = "POST",
        headers = headers,
        body = body_str
    })

    if not res then
        return nil, HTTP_INTERNAL_SERVER_ERROR, err
    end

    if res.status ~= HTTP_OK then
        return nil, res.status, res.body
    end

    local res_tab, err = core.json.decode(res.body)
    if not res_tab then
        return nil, HTTP_INTERNAL_SERVER_ERROR, err
    end

    if not res_tab.data or not res_tab.data[1] or not res_tab.data[1].embedding then
        return nil, HTTP_INTERNAL_SERVER_ERROR, "invalid response format"
    end

    -- Return the first embedding as current logic only handles one input for search
    return res_tab.data[1].embedding
end

local function get_headers(conf)
    local headers = {
        ["Content-Type"] = "application/json",
    }
    headers["Authorization"] = "Bearer " .. conf.api_key

    return headers
end

function _M.get_embeddings(conf, input)
    local headers = get_headers(conf)

    local body = {
        input = input,
        model = conf.model,
        dimensions = conf.dimensions
    }

    return request_embedding_vector(conf.endpoint, headers, body)
end

return _M
