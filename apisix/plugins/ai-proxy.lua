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
local constants = require("apisix.constants")
local require = require

local ngx_req = ngx.req
local ngx = ngx

local plugin_name = "ai-proxy"
local _M = {
    version = 0.5,
    priority = 1004,
    name = plugin_name,
    schema = schema,
}


function _M.check_schema(conf)
    local ai_driver = pcall(require, "apisix.plugins.ai-proxy.drivers." .. conf.model.provider)
    if not ai_driver then
        return false, "provider: " .. conf.model.provider .. " is not supported."
    end
    return core.schema.check(schema.plugin_schema, conf)
end


local CONTENT_TYPE_JSON = "application/json"


function _M.access(conf, ctx)
    local route_type = conf.route_type
    ctx.ai_proxy = {}

    local content_type = core.request.header(ctx, "Content-Type") or CONTENT_TYPE_JSON
    if content_type ~= CONTENT_TYPE_JSON then
        return 400, "unsupported content-type: " .. content_type
    end

    local request_table, err = core.request.get_request_body_table()
    if not request_table then
        return 400, err
    end

    local req_schema = schema.chat_request_schema
    if route_type == constants.COMPLETION then
        req_schema = schema.chat_completion_request_schema
    end
    local ok, err = core.schema.check(req_schema, request_table)
    if not ok then
        return 400, "request format doesn't match schema: " .. err
    end

    if conf.model.options and conf.model.options.response_streaming then
        request_table.stream = true
        ngx.ctx.disable_proxy_buffering = true
    end

    if conf.model.name then
        request_table.model = conf.model.name
    end

    local ai_driver = require("apisix.plugins.ai-proxy.drivers." .. conf.model.provider)
    local ok, err = ai_driver.configure_request(conf, request_table, ctx)
    if not ok then
        core.log.error("failed to configure request for AI service: ", err)
        return 500
    end

    if route_type ~= "passthrough" then
        local final_body, err = core.json.encode(request_table)
        if not final_body then
            core.log.error("failed to encode request body to JSON: ", err)
            return 500
        end
        ngx_req.set_body_data(final_body)
    end
end

return _M
