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
local core        = require("apisix.core")
local plugin_name = "proxy-rewrite"
local pairs       = pairs
local ipairs      = ipairs


local schema = {
    type = "object",
    properties = {
        uri = {
            description = "new uri for upstream",
            type        = "string",
            minLength   = 1,
            maxLength   = 4096
        },
        host = {
            description = "new host for upstream",
            type        = "string",
            pattern     = "^[0-9a-zA-Z-.]+$",
        },
        scheme = {
            description = "new scheme for upstream",
            type    = "string",
            enum    = {"http", "https"}
        },
        enable_websocket = {
            description = "enable websocket for request",
            type        = "boolean",
            default     = false
        },
        headers = {
            description = "new headers for request",
            type = "object",
            minProperties = 1,
        },
    },
    minProperties = 1,
}


local _M = {
    version  = 0.1,
    priority = 1008,
    name     = plugin_name,
    schema   = schema,
}


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end
    return true
end


do
    local upstream_vars = {
        scheme     = "upstream_scheme",
        host       = "upstream_host",
        upgrade    = "upstream_upgrade",
        connection = "upstream_connection",
    }
    local upstream_names = {}
    for name, _ in pairs(upstream_vars) do
        core.table.insert(upstream_names, name)
    end

function _M.rewrite(conf, ctx)
    for _, name in ipairs(upstream_names) do
        if conf[name] then
            ctx.var[upstream_vars[name]] = conf[name]
        end
    end

    local upstream_uri = conf.uri or ctx.var.uri
    if ctx.var.is_args == "?" then
        ctx.var.upstream_uri = upstream_uri .. "?" .. (ctx.var.args or "")
    else
        ctx.var.upstream_uri = upstream_uri
    end

    if conf.enable_websocket then
        ctx.var.upstream_upgrade    = ctx.var.http_upgrade
        ctx.var.upstream_connection = ctx.var.http_connection
    end

    -- TODO: support deleted header
    if conf.headers then
        for header_name, header_value in pairs(conf.headers) do
            core.request.set_header(header_name, header_value)
        end
    end
end

end  -- do


return _M
