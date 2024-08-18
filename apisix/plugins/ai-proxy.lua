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
    -- TODO: check custom URL correctness
    return core.schema.check(schema.plugin_schema, conf)
end


local CONTENT_TYPE_JSON = "application/json"


local function get_request_table()
    local req_body, err = core.request.get_body() -- TODO: max size
    if not req_body then
        return nil, "failed to get request body: " .. (err or "request body is empty")
    end
    req_body, err = req_body:gsub("\\\"", "\"") -- remove escaping in JSON
    if not req_body then
        return nil, "failed to remove escaping from body: " .. req_body .. ". err: " .. err
    end
    return core.json.decode(req_body)
end

function _M.access(conf, ctx)
    local route_type = conf.route_type
    ctx.ai_proxy = {}

    local content_type = core.request.header(ctx, "Content-Type") or CONTENT_TYPE_JSON
    if content_type ~= CONTENT_TYPE_JSON then
        return 400, "unsupported content-type: " .. content_type
    end

    local request_table, err = get_request_table()
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

    if route_type ~= "preserve" then
        ngx_req.set_body_data(core.json.encode(request_table))
    end

    local ai_driver = require("apisix.plugins.ai-proxy.drivers." .. conf.model.provider)
    local ok, err = ai_driver.configure_request(conf, ctx)
    if not ok then
        core.log.error("failed to configure request for AI service: ", err)
        return 500
    end
end

return _M
