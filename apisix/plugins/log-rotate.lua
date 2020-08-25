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
local process = require("ngx.process")
local signal = require("resty.signal")
local ngx = ngx
local prefix = ngx.config.prefix()
local lfs = require("lfs")
local io = io
local os = os
local table = table
local select = select
local type = type
local string = string
local local_conf


local timer
local plugin_name = "log-rotate"
local INTERVAL = 60 * 60    -- rotate interval (unit: second)
local MAX_KEPT = 24 * 7     -- max number of log files will be kept
local schema = {
    type = "object",
    properties = {},
    additionalProperties = false,
}


local _M = {
    version = 0.1,
    priority = 100,
    name = plugin_name,
    schema = schema,
}


local function file_exists(path)
    local file = io.open(path, "r")
    if file then
        file:close()
    end
    return file ~= nil
end


local function get_last_index(str, key)
    local rev = string.reverse(str)
    local _, idx = string.find(rev, key)
    local n
    if idx then
        n = string.len(rev) - idx + 1
    end

    return n
end


local function get_log_path_info(file_type)
    local_conf = core.config.local_conf()
    local confpath
    if file_type == "error.log" then
        confpath = local_conf and local_conf.nginx_config and
        local_conf.nginx_config.error_log
    else
        confpath = local_conf and local_conf.nginx_config and
        local_conf.nginx_config.http and
        local_conf.nginx_config.http.access_log
    end

    if confpath then
        local n = get_last_index(confpath, "/")
        if n ~= nil then
            local dir = string.sub(confpath, 1, n)
            local name = string.sub(confpath, n + 1)
            return dir, name
        end
    end

    return prefix .. "logs/", file_type
end


local function rotate_file(date_str, file_type)
    local log_dir, filename = get_log_path_info(file_type)

    local file_path = log_dir .. date_str .. "__" .. filename
    if file_exists(file_path) then
        core.log.info("file exist: ", file_path)
        return false
    end

    local file_path_org = log_dir .. filename
    os.rename(file_path_org, file_path)
    core.log.info("move file from ", file_path_org, " to ", file_path)
    return true
end


local function tab_sort(a, b)
    return a > b
end

local function scan_log_folder()
    local t = {
        access = {},
        error = {},
    }

    local log_dir, access_name = get_log_path_info("access.log")
    local _, error_name = get_log_path_info("error.log")

    for file in lfs.dir(log_dir) do
        local n = get_last_index(file, "__")
        if n ~= nil then
            local log_type = file:sub(n + 2)
            if log_type == access_name then
                table.insert(t.access, file)
            elseif log_type == error_name then
                table.insert(t.error, file)
            end
        end
    end

    table.sort(t.access, tab_sort)
    table.sort(t.error, tab_sort)
    return t
end


local function try_attr(t, ...)
    local count = select('#', ...)
    for i = 1, count do
        local attr = select(i, ...)
        t = t[attr]
        if type(t) ~= "table" then
            return false
        end
    end

    return true
end


local function rotate()
    local local_conf = core.config.local_conf()
    local interval = INTERVAL
    local max_kept = MAX_KEPT
    if try_attr(local_conf, "plugin_attr", "log-rotate") then
        local attr = local_conf.plugin_attr["log-rotate"]
        interval = attr.interval or interval
        max_kept = attr.max_kept or max_kept
    end

    local time = ngx.time()
    if time % interval == 0 then
        time = time - interval
    else
        time = time - time % interval
    end

    local date_str = os.date("%Y-%m-%d_%H-%M-%S", time)

    local ok1 = rotate_file(date_str, "access.log")
    local ok2 = rotate_file(date_str, "error.log")
    if not ok1 and not ok2 then
        return
    end

    core.log.warn("send USER1 signal to master process [", ngx.worker.pid(),
                  "] for reopening log file")
    local ok, err = signal.kill(ngx.worker.pid(), signal.signum("USR1"))
    if not ok then
        core.log.error("failed to send USER1 signal for reopening log file: ",
                       err)
    end

    -- clean the oldest file
    local log_list = scan_log_folder()
    local log_dir, _ = get_log_path_info("access.log")
    for i = max_kept + 1, #log_list.error do
        local path = log_dir .. log_list.error[i]
        local ok = os.remove(path)
        core.log.warn("remove old error file: ", path, " ret: ", ok)
    end

    for i = max_kept + 1, #log_list.access do
        local path = log_dir .. log_list.access[i]
        local ok = os.remove(path)
        core.log.warn("remove old access file: ", path, " ret: ", ok)
    end
end


function _M.init()
    core.log.info("enter log-rotate plugin, process type: ", process.type())

    if process.type() ~= "privileged agent" and process.type() ~= "single" then
        return
    end

    if timer then
        return
    end

    local err
    timer, err = core.timer.new("logrotate", rotate, {check_interval = 0.5})
    if not timer then
        core.log.error("failed to create timer log rotate: ", err)
    else
        core.log.notice("succeed to create timer: log rotate")
    end
end


return _M
