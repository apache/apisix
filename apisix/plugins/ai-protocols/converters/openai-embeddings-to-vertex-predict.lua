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

--- Converter: OpenAI Embeddings ↔ Vertex AI Predict.
-- Converts OpenAI embeddings format to Vertex AI predict format (request)
-- and Vertex AI predict format back to OpenAI embeddings format (response).

local core = require("apisix.core")
local type = type
local ipairs = ipairs

local _M = {
    from = "openai-embeddings",
    to = "vertex-predict",
}


function _M.convert_request(body, _)
    if not body then
        return nil, "empty openai request"
    end

    local input = body.input
    if not input then
        return nil, "`input` is required for embeddings"
    end

    local input_contexts = {}

    if type(input) == "string" then
        input_contexts = { input }
    elseif type(input) == "table" then
        for i, v in ipairs(input) do
            if type(v) == "string" then
                core.table.insert(input_contexts, v)
            elseif type(v) == "table" then
                core.table.insert(input_contexts, core.table.concat(v, " "))
            else
                return nil, "unsupported input type at index " .. i
            end
        end
    else
        return nil, "`input` must be string or array"
    end

    local instances = {}
    for _, text in ipairs(input_contexts) do
        core.table.insert(instances, { content = text })
    end

    return { instances = instances }
end


function _M.convert_response(body, ctx)
    if type(body) ~= "table" then
        return nil, "empty vertex response"
    end

    local predictions = body.predictions
    if type(predictions) ~= "table" then
        return nil, "vertex response missing predictions"
    end

    local data = {}
    local total_tokens = 0

    for i, pred in ipairs(predictions) do
        local emb = pred.embeddings or {}
        local values = emb.values
        if type(values) ~= "table" then
            return nil, "invalid embedding at index " .. i
        end

        if emb.statistics and emb.statistics.token_count then
            total_tokens = total_tokens + emb.statistics.token_count
        end

        core.table.insert(data, {
            object = "embedding",
            index = i - 1,
            embedding = values
        })
    end

    local model = ctx.var.request_llm_model or "unknown"
    return {
        object = "list",
        data = data,
        model = model,
        usage = {
            prompt_tokens = total_tokens,
            total_tokens = total_tokens,
        }
    }
end


return _M
