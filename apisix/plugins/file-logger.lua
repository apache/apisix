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
local log_util = require("apisix.utils.log-util")
local core = require("apisix.core")
local plugin = require("apisix.plugin")

local ngx = ngx
local pairs = pairs

local plugin_name = "file-logger"

local schema = {
    type = "object",
    properties = {
        path = {
            type = "string",
            require = true
        },
        custom_fields_by_lua = {
            type = "object",
            keys = {
                type = "string",
                len_min = 1
            },
            values = {
                type = "string",
                len_min = 1
            }
        }
    },
    required = {"path"}
}

local metadata_schema = {
    type = "object",
    properties = {
        log_format = log_util.metadata_schema_log_format
    }
}

local _M = {
    version = 0.1,
    priority = 399,
    name = plugin_name,
    schema = schema,
    metadata_schema = metadata_schema
}

function _M.check_schema(conf, schema_type)
    if schema_type == core.schema.TYPE_METADATA then
        return core.schema.check(metadata_schema, conf)
    end

    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return nil, err
    end
    return log_util.check_log_schema(conf)
end

local function write_file_data(conf, log_message)
    local msg = core.json.encode(log_message) .. "\n"
    local file = core.io.open(conf.path, 'a+')

    file:write(msg)
    file:close()
end

local function custom_fields_value(custom_lua_code)
    local result = core.loadstring(custom_lua_code)
    return result()
end

function _M.body_filter(conf, ctx)
    log_util.collect_body(conf, ctx)
end

function _M.log(conf, ctx)
    local metadata = plugin.plugin_metadata(plugin_name)
    local entry

    if metadata and metadata.value.log_format
        and core.table.nkeys(metadata.value.log_format) > 0
    then
        entry = log_util.get_custom_format_log(ctx, metadata.value.log_format)
    else
        entry = log_util.get_full_log(ngx, conf)
    end

    if conf.custom_fields_by_lua
        and core.table.nkeys(conf.custom_fields_by_lua) > 0
    then
        local set_log_fields_value = entry
        for key, expression in pairs(conf.custom_fields_by_lua) do
            set_log_fields_value[key] = custom_fields_value(expression)
        end
        write_file_data(conf, set_log_fields_value)
    else
        write_file_data(conf, entry)
    end
end

return _M
