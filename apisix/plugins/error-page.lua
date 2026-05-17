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
local plugin      = require("apisix.plugin")
local plugin_name = "error-page"
local ngx         = ngx


local metadata_schema = {
    type = "object",
    properties = {
        enable = {type = "boolean", default = false},
    },
    patternProperties = {
        ["^error_[1-5][0-9][0-9]$"] = {
            type = "object",
            properties = {
                body = {type = "string", minLength = 1},
                content_type = {type = "string", default = "text/html"},
            },
        },
    },
}

local schema = {}

local _M = {
    version         = 0.1,
    priority        = 450,
    name            = plugin_name,
    schema          = schema,
    metadata_schema = metadata_schema,
}


function _M.check_schema(conf, schema_type)
    if schema_type == core.schema.TYPE_METADATA then
        return core.schema.check(metadata_schema, conf)
    end
    return core.schema.check(schema, conf)
end


-- return metadata only if the response should be modified
local function get_metadata(ctx)
    local status = ngx.status
    if ctx.var.upstream_status then
        return nil
    end

    if status < 400 then
        return nil
    end

    local metadata = plugin.plugin_metadata(plugin_name)
    if not metadata then
        core.log.info("failed to read metadata for ", plugin_name)
        return nil
    end
    core.log.info(plugin_name, " metadata: ", core.json.delay_encode(metadata))
    metadata = metadata.value
    if not metadata.enable then
        return nil
    end

    local err_page = metadata["error_" .. status]
    if not err_page or not (err_page.body and #err_page.body > 0) then
        core.log.info("error page for error_", status, " not defined, default will be used.")
        return nil
    end

    return metadata
end


function _M.header_filter(conf, ctx)
    ctx.plugin_error_page_meta = get_metadata(ctx)
    if not ctx.plugin_error_page_meta then
        return
    end
    local status = ngx.status
    local err_page = ctx.plugin_error_page_meta["error_" .. status]
    core.response.set_header("content-type", err_page.content_type)
    core.response.set_header("content-length", #err_page.body)
end


function _M.body_filter(conf, ctx)
    if not ctx.plugin_error_page_meta then
        return
    end

    ngx.arg[1] = ctx.plugin_error_page_meta["error_" .. ngx.status].body
    ngx.arg[2] = true
end


return _M
