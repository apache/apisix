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
local ffi          =   require("ffi")
local bit          =   require("bit")

local C            =   ffi.C
local ngx          =   ngx
local pairs        =   pairs
local load_string  =   loadstring
local io_open      =    io.open

local plugin_name  =   "file-logger"
local O_CREAT      =   00000040 -- create and open
local O_APPEND     =   00000400 -- add content to the end of
local O_WRONLY     =   00000001 -- write only open
-- local O_APPEND     =   02000 -- add content to the end of
local S_IRUSR      =   00400    -- user has read permission
local S_IWUSR      =   00200    -- user has write permission
local S_IRGRP      =   00040    -- group has read permission
local S_IROTH      =   00004    -- others have read permission

local oflags = bit.bor(O_WRONLY, O_CREAT, O_APPEND)
local mode = bit.bor(S_IRUSR, S_IWUSR, S_IRGRP, S_IROTH)
local file_descriptors = {}

ffi.cdef [[
    int open(const char * filename, int flags, int mode);
    int write(int fd, const void * ptr, int numbytes);
    int close(int fd);
]]
local schema = {
    type = "object",
    properties = {
        path = {
            type = "string",
            require = true,
            match = [[^[^*&%%\`]+$]],
            err = "not a valid filename"
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

local function reopen()
    local args = ngx.req.get_uri_args()
    if args["path"] then
        local target_fd = io_open('logs/file_fd', 'w+')
        local fd = tonumber(target_fd:read())
        target_fd:write('-1')
        core.log.warn('read_file: ', fd)
        target_fd:close()
        C.close(fd)
    end
end

local function write_file_data(conf, log_message)
    local msg = core.json.encode(log_message) .. "\n"
    local find_file = io_open('logs/file_fd', 'w+')
    local reopen = tonumber(find_file:read())
    local fd = file_descriptors[conf.path]
    core.log.warn("reopen: ", reopen)

    if fd and reopen then
        if reopen < 0 then
            fd = nil
            file_descriptors[conf.path] = nil
        end
    end

    if not fd then
        local file = io_open(conf.path, 'a+')
        file:close()

        fd = C.open(conf.path, oflags, mode)
        if fd < 0 then
            local err = ffi.errno()
            core.log.error("failed to open file: " .. conf.path .. ", error info: " .. err)

        else
            find_file:write(fd)
            file_descriptors[conf.path] = fd
        end
    end

    find_file:close()
    C.write(fd, msg, #msg)
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
            set_log_fields_value[key] = load_string(expression)()
        end
        write_file_data(conf, set_log_fields_value)
    else
        write_file_data(conf, entry)
    end
end

function _M.control_api()
    return {
        {
            methods = {"GET"},
            uris ={"/v1/plugin/file-logger/reopen"},
            handler = reopen,
        }
    }
end

return _M
