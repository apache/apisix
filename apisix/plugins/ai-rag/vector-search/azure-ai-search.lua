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
            description = "The endpoint for the Azure AI Search service."
        },
        api_key = {
            type = "string",
            description = "The API key for authentication."
        },
        fields = {
            type = "string",
            description = "Comma-separated list of fields to retrieve"
        },
        exhaustive = {
            type = "boolean",
            default = true,
            description = "Whether to perform an exhaustive search."
        },
        select = {
            type = "string",
            description = "field to select in the response"
        },
        k = {
            type = "integer",
            minimum = 1,
            default = 5,
            description = "Number of nearest neighbors to return as top hits."
        }
    },
    required = { "endpoint", "api_key", "fields", "select" }
}


function _M.search(conf, embeddings)
    local body = {
        select = conf.select,
        vectorQueries = {
            {
                kind = "vector",
                vector = embeddings,
                fields = conf.fields,
                k = conf.k,
                exhaustive = conf.exhaustive
            }
        }
    }
    local final_body, err = core.json.encode(body)
    if not final_body then
        return nil, HTTP_INTERNAL_SERVER_ERROR, err
    end

    local httpc = http.new()
    local res, err = httpc:request_uri(conf.endpoint, {
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["api-key"] = conf.api_key,
        },
        body = final_body
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
    if not res_tab.value or #res_tab.value == 0 then
        return {}
    end
    local docs = {}
    for i = 1, #res_tab.value do
        local item = res_tab.value[i]
        docs[i] = item[conf.select]
    end

    return docs
end

return _M
