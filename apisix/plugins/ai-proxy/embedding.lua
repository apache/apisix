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

-- Batch embedding client for the semantic balancer. Routes the request through
-- the shared ai-provider layer (apisix.plugins.ai-providers.*) so endpoint
-- resolution, authentication and HTTP transport match the chat path, instead of
-- re-implementing them here. One call embeds a list of texts (OpenAI-compatible
-- /embeddings: input is an array), returning a vector per text. Keeps semantic
-- routing free of a vector database.
local core = require("apisix.core")
local ipairs = ipairs
local type = type
local tostring = tostring
local require = require
local pcall = pcall
local INF = math.huge

local _M = {}

local EMBEDDINGS_PROTOCOL = "openai-embeddings"


-- The provider's embeddings capability supplies a default path when it has one
-- (openai: /v1/embeddings). Providers whose endpoint always carries its own path
-- (azure-openai) declare none, and build_request then requires `endpoint` to give
-- it. Which providers are allowed is gated by the `embeddings.provider` enum, so
-- a missing capability is not an error here.
local function embeddings_target_path(ai_provider)
    local cap = ai_provider.capabilities and ai_provider.capabilities[EMBEDDINGS_PROTOCOL]
    if not cap then
        return nil
    end
    local path = cap.path
    if type(path) == "function" then
        path = path()
    end
    return path
end


-- Fetch embeddings for `texts` in a single batch request.
-- Returns an array of vectors index-aligned with `texts`, or nil + err.
function _M.fetch(conf, texts)
    if not texts or #texts == 0 then
        return {}
    end

    if not conf.model or conf.model == "" then
        return nil, "embedding model is not configured"
    end

    local ok, ai_provider = pcall(require, "apisix.plugins.ai-providers." .. conf.provider)
    if not ok then
        return nil, "failed to load ai-provider: " .. tostring(conf.provider)
    end

    local target_path = embeddings_target_path(ai_provider)

    -- The embedding call is a self-contained sidecar request. It sets none of the
    -- opts.client_* fields, so build_request forwards none of the client's headers
    -- (Authorization, Cookie, ...) or query to the embedding provider, and the pure
    -- request client always sends our { model, input } body rather than the
    -- client's request body.
    local extra_opts = {
        endpoint = conf.endpoint,
        auth = conf.auth,
        target_path = target_path,
    }
    local req_conf = {
        ssl_verify = conf.ssl_verify ~= false,
        timeout = conf.timeout or 3000,
        keepalive = true,
    }

    local status, raw_body, err = ai_provider:request(req_conf,
        { model = conf.model, input = texts }, extra_opts)
    -- The upstream body never reaches a log line or a returned error. It is
    -- untrusted third-party content that may echo the prompt back, be arbitrarily
    -- large, or forge log lines with newlines. Report the status and a bounded,
    -- sanitized summary instead.
    if status ~= 200 then
        if err then
            return nil, "embedding request failed: " .. err
        end
        return nil, "embedding endpoint returned status " .. tostring(status)
    end

    -- A 200 body that decodes to a scalar, boolean or null must not be indexed
    -- (`data.data` on a number raises). `derr` is cjson's own parse error, which
    -- is bounded and carries no body content.
    local data, derr = core.json.decode(raw_body)
    if type(data) ~= "table" or type(data.data) ~= "table" then
        return nil, "invalid embedding response: " .. (derr or "unexpected shape")
    end

    local vectors = {}
    for i, item in ipairs(data.data) do
        -- `data` may be an array of non-objects; indexing those would raise and
        -- turn a sidecar failure into a 500, so check before touching a field.
        if type(item) ~= "table" then
            return nil, "invalid embedding entry at index " .. (i - 1)
        end
        -- OpenAI returns an `index`; fall back to positional order. It must be a
        -- usable table key: cjson decodes JSON `NaN` to a number, and `t[NaN]`
        -- raises. A float or out-of-range index is equally unusable.
        local idx = i
        local raw_idx = item.index
        if type(raw_idx) == "number" then
            if raw_idx ~= raw_idx or raw_idx < 0 or raw_idx >= #texts
               or raw_idx % 1 ~= 0
            then
                return nil, "invalid embedding index at entry " .. (i - 1)
            end
            idx = raw_idx + 1
        end
        local emb = item.embedding
        if type(emb) ~= "table" or #emb == 0 then
            return nil, "invalid embedding vector at index " .. (idx - 1)
        end
        for _, n in ipairs(emb) do
            -- reject non-finite components: cjson decodes `1e999` to inf, which
            -- would normalize to NaN and silently poison every similarity score.
            if type(n) ~= "number" or n ~= n or n == INF or n == -INF then
                return nil, "non-numeric embedding component at index " .. (idx - 1)
            end
        end
        vectors[idx] = emb
    end

    -- Every input position must have produced a vector; a hole means a
    -- dropped/duplicated index we must not silently route on. Checking each
    -- slot is reliable where `#vectors` is not on a sparse table.
    for i = 1, #texts do
        if vectors[i] == nil then
            return nil, "missing embedding for input index " .. (i - 1)
        end
    end
    return vectors
end


return _M
