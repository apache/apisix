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
local timers = require("apisix.timers")
local plugin = require("apisix.plugin")
local process = require("ngx.process")
local signal = require("resty.signal")
local shell = require("resty.shell")
local ipairs = ipairs
local ngx = ngx
local ngx_time = ngx.time
local ngx_update_time = ngx.update_time
local lfs = require("lfs")
local type = type
local io_open = io.open
local os_date = os.date
local os_remove = os.remove
local os_rename = os.rename
local str_sub = string.sub
local str_format = string.format
local str_byte = string.byte
local ngx_sleep = require("apisix.core.utils").sleep
local string_rfind = require("pl.stringx").rfind
local local_conf
local enable_access_log


local plugin_name = "log-rotate"
local INTERVAL = 60 * 60    -- rotate interval (unit: second)
local MAX_KEPT = 24 * 7     -- max number of log files will be kept
local MAX_SIZE = -1         -- max size of file will be rotated
local COMPRESSION_FILE_SUFFIX = ".tar.gz" -- compression file suffix
local rotate_time
local default_logs
local enable_compression = false
local DEFAULT_ACCESS_LOG_FILENAME = "access.log"
local DEFAULT_ERROR_LOG_FILENAME = "error.log"
local SLASH_BYTE = str_byte("/")

local schema = {
    type = "object",
    properties = {},
}


local _M = {
    version = 0.1,
    priority = 100,
    name = plugin_name,
    schema = schema,
    scope = "global",
}


local function file_exists(path)
    local file = io_open(path, "r")
    if file then
        file:close()
    end
    return file ~= nil
end


local function get_log_path_info(file_type)
    local conf_path
    if file_type == "error.log" then
        conf_path = local_conf and local_conf.nginx_config and
        local_conf.nginx_config.error_log
    else
        conf_path = local_conf and local_conf.nginx_config and
        local_conf.nginx_config.http and
        local_conf.nginx_config.http.access_log
    end

    local prefix = ngx.config.prefix()

    if conf_path then
        -- relative path
        if str_byte(conf_path) ~= SLASH_BYTE then
            conf_path = prefix .. conf_path
        end
        local n = string_rfind(conf_path, "/")
        if n ~= nil and n ~= #conf_path then
            local dir = str_sub(conf_path, 1, n)
            local name = str_sub(conf_path, n + 1)
            return dir, name
        end
    end

    return prefix .. "logs/", file_type
end


local function tab_sort_comp(a, b)
    return a > b
end


local function scan_log_folder(log_file_name)
    local t = {}

    local log_dir, log_name = get_log_path_info(log_file_name)

    local compression_log_type = log_name .. COMPRESSION_FILE_SUFFIX
    for file in lfs.dir(log_dir) do
        local n = string_rfind(file, "__")
        if n ~= nil then
            local log_type = file:sub(n + 2)
            if log_type == log_name or log_type == compression_log_type then
                core.table.insert(t, file)
            end
        end
    end

    core.table.sort(t, tab_sort_comp)
    return t, log_dir
end


local function rename_file(log, date_str)
    local new_file
    if not log.new_file then
        core.log.warn(log.type, " is off")
        return
    end

    new_file = str_format(log.new_file, date_str)
    if file_exists(new_file) then
        core.log.info("file exist: ", new_file)
        return new_file
    end

    local ok, err = os_rename(log.file, new_file)
    if not ok then
        core.log.error("move file from ", log.file, " to ", new_file,
                       " res:", ok, " msg:", err)
        return
    end

    return new_file
end


local function compression_file(new_file, timeout)
    if not new_file or type(new_file) ~= "string" then
        core.log.info("compression file: ", new_file, " invalid")
        return
    end

    local n = string_rfind(new_file, "/")
    local new_filepath = str_sub(new_file, 1, n)
    local new_filename = str_sub(new_file, n + 1)
    local com_filename = new_filename .. COMPRESSION_FILE_SUFFIX
    local cmd = str_format("cd %s && tar -zcf %s %s", new_filepath,
            com_filename, new_filename)
    core.log.info("log file compress command: " .. cmd)

    local ok, stdout, stderr, reason, status = shell.run(cmd, nil, timeout, nil)
    if not ok then
        core.log.error("compress log file from ", new_filename, " to ", com_filename,
                       " fail, stdout: ", stdout, " stderr: ", stderr, " reason: ", reason,
                       " status: ", status)
        return
    end

    ok, stderr = os_remove(new_file)
    if stderr then
        core.log.error("remove uncompressed log file: ", new_file,
                       " fail, err: ", stderr, "  res:", ok)
    end
end


local function init_default_logs(logs_info, log_type)
    local filepath, filename = get_log_path_info(log_type)
    logs_info[log_type] = { type = log_type }
    if filename ~= "off" then
        logs_info[log_type].file = filepath .. filename
        logs_info[log_type].new_file = filepath .. "/%s__" .. filename
    end
end


local function file_size(file)
    local attr = lfs.attributes(file)
    if attr then
        return attr.size
    end
    return 0
end


local function rotate_file(files, now_time, max_kept, timeout)
    if core.table.isempty(files) then
        return
    end

    local new_files = core.table.new(#files, 0)
    -- rename the log files
    for _, file in ipairs(files) do
        local now_date = os_date("%Y-%m-%d_%H-%M-%S", now_time)
        local new_file = rename_file(default_logs[file], now_date)
        if not new_file then
            return
        end

        core.table.insert(new_files, new_file)
    end

    -- send signal to reopen log files
    local pid = process.get_master_pid()
    core.log.warn("send USR1 signal to master process [", pid, "] for reopening log file")
    local ok, err = signal.kill(pid, signal.signum("USR1"))
    if not ok then
        core.log.error("failed to send USR1 signal for reopening log file: ", err)
    end

    if enable_compression then
        -- Waiting for nginx reopen files
        -- to avoid losing logs during compression
        ngx_sleep(0.5)

        for _, new_file in ipairs(new_files) do
            compression_file(new_file, timeout)
        end
    end

    for _, file in ipairs(files) do
        -- clean the oldest file
        local log_list, log_dir = scan_log_folder(file)
        for i = max_kept + 1, #log_list do
            local path = log_dir .. log_list[i]
            local ok, err = os_remove(path)
            if err then
               core.log.error("remove old log file: ", path, " err: ", err, "  res:", ok)
            end
        end
    end
end


local function rotate()
    local interval = INTERVAL
    local max_kept = MAX_KEPT
    local max_size = MAX_SIZE
    local attr = plugin.plugin_attr(plugin_name)
    local timeout = 10000 -- default timeout 10 seconds
    if attr then
        interval = attr.interval or interval
        max_kept = attr.max_kept or max_kept
        max_size = attr.max_size or max_size
        timeout = attr.timeout or timeout
        enable_compression = attr.enable_compression or enable_compression
    end

    core.log.info("rotate interval:", interval)
    core.log.info("rotate max keep:", max_kept)
    core.log.info("rotate max size:", max_size)
    core.log.info("rotate timeout:", timeout)

    if not default_logs then
        -- first init default log filepath and filename
        default_logs = {}
        init_default_logs(default_logs, DEFAULT_ACCESS_LOG_FILENAME)
        init_default_logs(default_logs, DEFAULT_ERROR_LOG_FILENAME)
    end

    ngx_update_time()
    local now_time = ngx_time()
    if not rotate_time then
        -- first init rotate time
        rotate_time = now_time + interval - (now_time % interval)
        core.log.info("first init rotate time is: ", rotate_time)
        return
    end

    if now_time >= rotate_time then
        local files = {DEFAULT_ERROR_LOG_FILENAME}
        if enable_access_log then
            core.table.insert(files, DEFAULT_ACCESS_LOG_FILENAME)
        end

        rotate_file(files, now_time, max_kept, timeout)

        -- reset rotate time
        rotate_time = rotate_time + interval

    elseif max_size > 0 then
        local access_log_file_size = file_size(default_logs[DEFAULT_ACCESS_LOG_FILENAME].file)
        local error_log_file_size = file_size(default_logs[DEFAULT_ERROR_LOG_FILENAME].file)
        local files = {}

        if enable_access_log and access_log_file_size >= max_size then
            core.table.insert(files, DEFAULT_ACCESS_LOG_FILENAME)
        end

        if error_log_file_size >= max_size then
            core.table.insert(files, DEFAULT_ERROR_LOG_FILENAME)
        end

        rotate_file(files, now_time, max_kept, timeout)
    end
end


function _M.init()
    if not local_conf then
        local_conf = core.config.local_conf()
    end
    local nginx_config = local_conf and local_conf.nginx_config
    enable_access_log = nginx_config and nginx_config.http and nginx_config.http.enable_access_log
    timers.register_timer("plugin#log-rotate", rotate, true)
end


function _M.destroy()
    timers.unregister_timer("plugin#log-rotate", true)
end


return _M
