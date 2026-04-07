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
local str_fmt = string.format

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


return require("apisix.plugins.ai-providers.base").new({
    get_node = get_node,
    capabilities = {
        ["openai-chat"] = {
            host = function(conf)
                return conf.region and get_host(conf.region)
            end,
            path = function(conf)
                if conf.project_id and conf.region then
                    return get_chat_completions_path(conf.project_id, conf.region)
                end
            end,
        },
        ["vertex-predict"] = {
            host = function(conf)
                return conf.region and get_host(conf.region)
            end,
            path = function(conf, ctx)
                if conf.project_id and conf.region then
                    local model = ctx and ctx.var.llm_model
                    return get_embeddings_path(conf.project_id, conf.region, model)
                end
            end,
        },
    },
})
