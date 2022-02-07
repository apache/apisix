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
local str_find = string.find
local str_format = string.format
local str_reverse = string.reverse
local tab_insert = table.insert
local tab_sort = table.sort

local local_conf


local plugin_name = "log-rotate"
local INTERVAL = 60 * 60    -- rotate interval (unit: second)
local MAX_KEPT = 24 * 7     -- max number of log files will be kept
local COMPRESSION_FILE_SUFFIX = ".tar.gz" -- compression file suffix
local rotate_time
local default_logs
local enable_compression = false
local DEFAULT_ACCESS_LOG_FILENAME = "access.log"
local DEFAULT_ERROR_LOG_FILENAME = "error.log"

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


local function get_last_index(str, key)
    local rev = str_reverse(str)
    local _, idx = str_find(rev, key)
    local n
    if idx then
        n = #rev - idx + 1
    end

    return n
end


local function get_log_path_info(file_type)
    local_conf = core.config.local_conf()
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
        local root = str_sub(conf_path, 1, 1)
        -- relative path
        if root ~= "/" then
            conf_path = prefix .. conf_path
        end
        local n = get_last_index(conf_path, "/")
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


local function scan_log_folder()
    local t = {
        access = {},
        error = {},
    }

    local log_dir, access_name = get_log_path_info("access.log")
    local _, error_name = get_log_path_info("error.log")

    if enable_compression then
        access_name = access_name .. COMPRESSION_FILE_SUFFIX
        error_name = error_name .. COMPRESSION_FILE_SUFFIX
    end

    for file in lfs.dir(log_dir) do
        local n = get_last_index(file, "__")
        if n ~= nil then
            local log_type = file:sub(n + 2)
            if log_type == access_name then
                tab_insert(t.access, file)
            elseif log_type == error_name then
                tab_insert(t.error, file)
            end
        end
    end

    tab_sort(t.access, tab_sort_comp)
    tab_sort(t.error, tab_sort_comp)
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


local function compression_file(new_file)
    if not new_file or type(new_file) ~= "string" then
        core.log.info("compression file: ", new_file, " invalid")
        return
    end

    local n = get_last_index(new_file, "/")
    local new_filepath = str_sub(new_file, 1, n)
    local new_filename = str_sub(new_file, n + 1)
    local com_filename = new_filename .. COMPRESSION_FILE_SUFFIX
    local cmd = str_format("cd %s && tar -zcf %s %s", new_filepath,
            com_filename, new_filename)
    core.log.info("log file compress command: " .. cmd)

    local ok, stdout, stderr, reason, status = shell.run(cmd)
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


local function rotate()
    local interval = INTERVAL
    local max_kept = MAX_KEPT
    local attr = plugin.plugin_attr(plugin_name)
    if attr then
        interval = attr.interval or interval
        max_kept = attr.max_kept or max_kept
        enable_compression = attr.enable_compression or enable_compression
    end

    core.log.info("rotate interval:", interval)
    core.log.info("rotate max keep:", max_kept)

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
        rotate_time = now_time + interval
        core.log.info("first init rotate time is: ", rotate_time)
        return
    end

    if now_time < rotate_time then
        -- did not reach the rotate time
        core.log.info("rotate time: ", rotate_time, " now time: ", now_time)
        return
    end

    local now_date = os_date("%Y-%m-%d_%H-%M-%S", now_time)
    local access_new_file = rename_file(default_logs[DEFAULT_ACCESS_LOG_FILENAME], now_date)
    local error_new_file = rename_file(default_logs[DEFAULT_ERROR_LOG_FILENAME], now_date)
    if not access_new_file and not error_new_file then
        -- reset rotate time
        rotate_time = rotate_time + interval
        return
    end

    core.log.warn("send USR1 signal to master process [",
                  process.get_master_pid(), "] for reopening log file")
    local ok, err = signal.kill(process.get_master_pid(), signal.signum("USR1"))
    if not ok then
        core.log.error("failed to send USR1 signal for reopening log file: ", err)
    end

    if enable_compression then
        compression_file(access_new_file)
        compression_file(error_new_file)
    end

    -- clean the oldest file
    local log_list, log_dir = scan_log_folder()
    for i = max_kept + 1, #log_list.error do
        local path = log_dir .. log_list.error[i]
        ok, err = os_remove(path)
        if err then
           core.log.error("remove old error file: ", path, " err: ", err, "  res:", ok)
        end
    end

    for i = max_kept + 1, #log_list.access do
        local path = log_dir .. log_list.access[i]
        ok, err = os_remove(path)
        if err then
           core.log.error("remove old error file: ", path, " err: ", err, "  res:", ok)
        end
    end

    -- reset rotate time
    rotate_time = rotate_time + interval
end


function _M.init()
    timers.register_timer("plugin#log-rotate", rotate, true)
end


function _M.destroy()
    timers.unregister_timer("plugin#log-rotate", true)
end


return _M
