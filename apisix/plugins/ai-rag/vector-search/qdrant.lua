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
local next = next
local ipairs = ipairs
local str_gsub = string.gsub
local ngx_escape_uri = ngx.escape_uri
local HTTP_OK = ngx.HTTP_OK
local HTTP_BAD_REQUEST = ngx.HTTP_BAD_REQUEST
local HTTP_BAD_GATEWAY = ngx.HTTP_BAD_GATEWAY

local _M = {}

_M.schema = {
    type = "object",
    properties = {
        endpoint = {
            type = "string",
            pattern = [[^https?://]],
        },
        api_key = {
            type = "string",
        },
        collection_name = {
            type = "string",
            minLength = 1,
        },
    },
    required = { "endpoint", "collection_name" },
    additionalProperties = false,
}


_M.request_schema = {
    type = "object",
    properties = {
        limit = {
            type = "integer",
            minimum = 1,
            maximum = 100,
        },
        using = {
            type = "string",
            minLength = 1,
        },
        filter = {
            type = "object",
        },
        params = {
            type = "object",
        },
        score_threshold = {
            type = "number",
        },
        with_payload = {
            type = "array",
            items = { type = "string", minLength = 1 },
            minItems = 1,
        },
    },
    additionalProperties = false,
}


function _M.search(conf, search_body, httpc, ssl_verify)
    local body = core.json.canonical_encode({
        query = search_body.embeddings,
        using = search_body.using,
        limit = search_body.limit,
        filter = search_body.filter,
        params = search_body.params,
        score_threshold = search_body.score_threshold,
        with_payload = search_body.with_payload or true,
    })

    local uri = str_gsub(conf.endpoint, "/+$", "") .. "/collections/"
                .. ngx_escape_uri(conf.collection_name) .. "/points/query"
    local res, err = httpc:request_uri(uri, {
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["api-key"] = conf.api_key,
        },
        body = body,
        ssl_verify = ssl_verify,
    })
    if not res then
        core.log.error("failed to query Qdrant: ", err)
        return nil, HTTP_BAD_GATEWAY, "vector search failed"
    end

    if res.status ~= HTTP_OK then
        core.log.error("Qdrant returned status ", res.status, ": ", res.body)
        if res.status == HTTP_BAD_REQUEST or res.status == 422 then
            return nil, HTTP_BAD_REQUEST, "invalid vector search query"
        end
        return nil, HTTP_BAD_GATEWAY, "vector search failed"
    end

    local data = core.json.decode(res.body)
    local points = type(data) == "table" and type(data.result) == "table"
                   and data.result.points
    if type(points) ~= "table" then
        core.log.error("invalid Qdrant response: ", res.body)
        return nil, HTTP_BAD_GATEWAY, "vector search failed"
    end

    local payloads = {}
    for _, point in ipairs(points) do
        if type(point.payload) == "table" and next(point.payload) then
            core.table.insert(payloads, point.payload)
        end
    end

    if #payloads == 0 then
        core.log.info("no Qdrant payloads matched the query")
        return ""
    end

    return core.json.canonical_encode(payloads)
end


return _M
