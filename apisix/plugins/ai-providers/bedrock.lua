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
local ngx_escape_uri = ngx.escape_uri
local os = os

local host_template = "bedrock-runtime.%s.amazonaws.com"
local chat_path_template = "/model/%s/converse"

local function get_host(region)
    return str_fmt(host_template, region)
end


local function get_region(instance_conf)
    return core.table.try_read_attr(instance_conf, "provider_conf", "region")
        or os.getenv("AWS_REGION") or "us-east-1"
end


local function get_node(instance_conf)
    return {
        scheme = "https",
        host = get_host(get_region(instance_conf)),
        port = 443,
    }
end


return require("apisix.plugins.ai-providers.base").new({
    get_node = get_node,
    remove_model = true,
    capabilities = {
        ["bedrock-converse"] = {
            host = function(conf)
                local region = conf.region or os.getenv("AWS_REGION") or "us-east-1"
                return get_host(region)
            end,
            path = function(conf, ctx)
                local model = ctx and ctx.var.llm_model
                if not model then return nil end
                -- URL-encode the model ID to handle ARNs containing : and /
                return str_fmt(chat_path_template, ngx_escape_uri(model))
            end,
        },
    },
})
