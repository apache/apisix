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
local schema = require("apisix.plugins.ai-proxy.schema")
local base = require("apisix.plugins.ai-proxy.base")

local require = require
local pcall = pcall

local plugin_name = "ai-proxy"
local _M = {
    version = 0.5,
    priority = 999,
    name = plugin_name,
    schema = schema,
}


function _M.check_schema(conf)
    local ai_driver = pcall(require, "apisix.plugins.ai-drivers." .. conf.model.provider)
    if not ai_driver then
        return false, "provider: " .. conf.model.provider .. " is not supported."
    end
    return core.schema.check(schema.ai_proxy_schema, conf)
end


local function get_model_name(conf)
    return conf.model.name
end


local function proxy_request_to_llm(conf, request_table, ctx)
    local ai_driver = require("apisix.plugins.ai-drivers." .. conf.model.provider)
    local extra_opts = {
        endpoint = core.table.try_read_attr(conf, "override", "endpoint"),
        query_params = conf.auth.query or {},
        headers = (conf.auth.header or {}),
        model_options = conf.model.options
    }
    local res, err, httpc = ai_driver:request(conf, request_table, extra_opts)
    if not res then
        return nil, err, nil
    end
    return res, nil, httpc
end

_M.access = base.new(proxy_request_to_llm, get_model_name)

return _M
