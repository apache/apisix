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
local type = type
local ipairs = ipairs

local _M = {}

_M.schema = {
    type = "object",
    properties = {
        endpoint = {
            type = "string",
            default = "https://api.cohere.ai/v2/rerank",
            description = "The endpoint for the Cohere Rerank API."
        },
        api_key = {
            type = "string",
            description = "The API key for authentication."
        },
        model = {
            type = "string",
            description = "The model to use for reranking."
        },
        top_n = {
            type = "integer",
            minimum = 1,
            default = 3,
            description = "The number of top results to return."
        }
    },
    required = { "api_key", "model" }
}

function _M.rerank(conf, docs, query)
    if not docs or #docs == 0 then
        return docs
    end

    local top_n = conf.top_n or 3
    if #docs <= top_n then
        return docs
    end

    -- Construct documents for Cohere Rerank API
    local documents = {}
    for _, doc in ipairs(docs) do
        local doc_content = doc
        if type(doc) == "table" then
            doc_content = doc.content or core.json.encode(doc)
        end
        core.table.insert(documents, doc_content)
    end

    local body = {
        model = conf.model,
        query = query,
        top_n = top_n,
        documents = documents
    }

    local body_str, err = core.json.encode(body)
    if not body_str then
        core.log.error("failed to encode rerank body: ", err)
        return docs -- fallback
    end

    local httpc = http.new()
    local res, err = httpc:request_uri(conf.endpoint, {
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Bearer " .. conf.api_key
        },
        body = body_str
    })

    if not res or res.status ~= 200 then
        core.log.error("rerank failed: ", err or (res and res.status))
        return docs -- fallback
    end

    local res_body = core.json.decode(res.body)
    if not res_body or not res_body.results then
        return docs
    end

    local new_docs = {}
    for _, result in ipairs(res_body.results) do
        -- The Cohere Rerank API returns 0-based indices; Lua tables are 1-based.
        -- Convert by adding 1 to access the correct document in the docs table.
        local idx = result.index + 1
        local doc = docs[idx]
        if doc then
            core.table.insert(new_docs, doc)
        end
    end

    return new_docs
end

return _M
