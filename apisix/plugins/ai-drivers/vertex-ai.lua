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
local string = string
local str_fmt = string.format
local type = type
local ipairs = ipairs

local host_template_fmt =
        "%s-aiplatform.googleapis.com"
local embeddings_path_template_fmt =
        "/v1/projects/%s/locations/%s/publishers/google/models/%s:predict"
local chat_completions_path_template_fmt =
        "/v1beta1/projects/%s/locations/%s/endpoints/openapi/chat/completions"

local function get_host(region)
    return str_fmt(host_template_fmt, region)
end


local function get_chat_completions_path(project_id, region)
    return str_fmt(chat_completions_path_template_fmt, project_id, region)
end


local function get_embeddings_path(project_id, region, model)
    return str_fmt(embeddings_path_template_fmt, project_id, region, model)
end


local function get_node(instance_conf)
    local host = "aiplatform.googleapis.com"
    local region = core.table.try_read_attr(instance_conf, "provider_conf", "region")
    if region then
        host = get_host(region)
    end
    return {
        scheme = "https",
        host = host,
        port = 443,
    }
end

local function openai_embeddings_to_vertex_predict(openai_req)
    if not openai_req then
        return nil, "empty openai request"
    end

    local input = openai_req.input
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
        core.table.insert(instances, {
            content = text
        })
    end

    return {
        instances = instances
    }
end

local function vertex_predict_to_openai_embeddings(vertex_resp, openai_model)
    if type(vertex_resp) ~= "table" then
        return nil, "empty vertex response"
    end

    local predictions = vertex_resp.predictions
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

    return {
        object = "list",
        data = data,
        model = openai_model or "unknown",
        usage = {
            prompt_tokens = total_tokens,
            total_tokens = total_tokens,
        }
    }
end


local function request_filter(conf, ctx, http_params)
    local body = http_params.body
    if body and body.input then
        ctx.llm_request_type = "embeddings"
        local vertex_req, err = openai_embeddings_to_vertex_predict(body)
        if not vertex_req then
            return nil, "failed to convert to vertex predict request: " .. err
        end
        http_params.body = vertex_req
        core.log.debug("using embeddings endpoint for Vertex AI")
    else
        ctx.llm_request_type = "chat_completions"
    end
    ctx.llm_request_model = body and body.model

    if conf.project_id and conf.region then
        if not http_params.path then
            local path
            if ctx.llm_request_type == "embeddings" then
                path = get_embeddings_path(conf.project_id, conf.region, body.model)
            else
                path = get_chat_completions_path(conf.project_id, conf.region)
            end
            http_params.path = path
        end
        if not http_params.host then
            http_params.host = get_host(conf.region)
        end
    end
end


local function response_filter(conf, ctx, resp)
    if ctx.llm_request_type == "embeddings" then
        local vertex_body = resp.body
        local openai_resp, err = vertex_predict_to_openai_embeddings(vertex_body,
                                                                    ctx.llm_request_model)
        if not openai_resp then
            return 500, "failed to convert to openai embeddings response: " .. err
        end
        resp.body = openai_resp
    end
end


return require("apisix.plugins.ai-drivers.openai-base").new({
    get_node = get_node,
    request_filter = request_filter,
    response_filter = response_filter,
})
