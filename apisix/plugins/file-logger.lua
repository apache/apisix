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
local log_util     =   require("apisix.utils.log-util")
local core         =   require("apisix.core")
local plugin       =   require("apisix.plugin")
local ngx          =   ngx
local io_open      =   io.open


local plugin_name  =   "file-logger"
local file


local schema = {
    type = "object",
    properties = {
        path = {
            type = "string",
            pattern = [[^[^*&%%\`]+$]],
            err = "not a valid filename"
        },
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

    if not file then
        file = io_open(conf.path, 'a+')
    end

    file:write(msg)
    file:flush()
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

    write_file_data(conf, entry)
end


return _M
