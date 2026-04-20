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

local host_template = "bedrock-runtime.%s.amazonaws.com"
local chat_path_template = "/model/%s/converse"

local function get_host(region)
    return str_fmt(host_template, region)
end


local function get_region(instance_conf)
    return core.table.try_read_attr(instance_conf, "provider_conf", "region")
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
    aws_sigv4 = true,
    capabilities = {
        ["bedrock-converse"] = {
            host = function(conf)
                if not conf.region then
                    return nil
                end
                return get_host(conf.region)
            end,
            path = function(conf, ctx)
                local model = ctx and ctx.var.llm_model
                if not model then return nil end
                -- Encode the model so it stays as a single path segment.
                -- Required for application inference profile ARNs which
                -- contain "/" (e.g. "...:application-inference-profile/abc")
                -- and ":". auth-aws.lua's normalize_and_encode_path is
                -- idempotent so this pre-encoding is preserved end-to-end.
                return str_fmt(chat_path_template, ngx_escape_uri(model))
            end,
        },
    },
})
