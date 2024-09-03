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
local require = require
local pcall = pcall

local ngx_req = ngx.req

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
    local ct = core.request.header(ctx, "Content-Type") or CONTENT_TYPE_JSON
    if not core.string.has_prefix(ct, CONTENT_TYPE_JSON) then
        return 400, "unsupported content-type: " .. ct
    end

    local request_table, err = core.request.get_request_body_table()
    if not request_table then
        return 400, err
    end

    local ok, err = core.schema.check(schema.chat_request_schema, request_table)
    if not ok then
        return 400, "request format doesn't match schema: " .. err
    end

    if conf.model.options and conf.model.options.stream then
        request_table.stream = true
        ngx.ctx.disable_proxy_buffering = true
    end

    if conf.model.name then
        request_table.model = conf.model.name
    end
    ctx.request_table = request_table
end


function _M.delayed_access(conf, ctx)
    local request_table = ctx.request_table
    local ai_driver = require("apisix.plugins.ai-proxy.drivers." .. conf.model.provider)
    local res, err, httpc = ai_driver.request(conf, request_table, ctx)
    if not res then
        core.log.error("failed to send request to AI service: ", err)
        return 500
    end


    if core.table.try_read_attr(conf, "model", "options", "stream") then
        local chunk, err
        local content_length = 0
        while true do
            chunk, err = res.body_reader() -- will read chunk by chunk
            if err then
                core.log.error("failed to read response chunk: ", err)
                return 500
            end
            content_length = content_length + (#chunk or 0)
            ngx.print(chunk)
            ngx.flush(true)
        end
        core.response.set_header("Content-Length", content_length)
        httpc:set_keepalive(10000, 100)
    else
        local res_body, err = res:read_body()
        if not res_body then
            core.log.error("failed to read response body: ", err)
            return 500
        end
        return res.status, res_body
    end
end

return _M
