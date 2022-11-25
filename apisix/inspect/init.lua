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
local dbg = require("apisix.inspect.dbg")
local lfs = require("lfs")
local cjson = require("cjson")
local io = io
local table_insert = table.insert
local loadfile = loadfile
local pcall = pcall
local ipairs = ipairs
local os = os
local ngx = ngx

local _M = {}

local last_modified = 0

local stop = false

local running = false

local last_report_time = 0

local REPORT_INTERVAL = 30 -- secs

local function is_file_exists(file)
   local f = io.open(file, "r")
   if f then io.close(f) return true else return false end
end

local function setup_hooks(file)
    if is_file_exists(file) then
        dbg.unset_all()
        local chunk = loadfile(file)
        local _, err = pcall(chunk)
        local hooks = {}
        for _, hook in ipairs(dbg.hooks()) do
            table_insert(hooks, hook.key)
        end
        core.log.info("set hooks: err=", err, ", hooks=", cjson.encode(hooks))
    end
end

local function reload_hooks(premature, delay, file)
    if premature or stop then
        stop = false
        running = false
        return
    end

    local time, err = lfs.attributes(file, 'modification')
    if err then
        if last_modified ~= 0 then
            core.log.info(err, ", disable all hooks")
            dbg.unset_all()
            last_modified = 0
        end
    elseif time ~= last_modified then
        setup_hooks(file)
        last_modified = time
    else
        local ts = os.time()
        if ts - last_report_time >= REPORT_INTERVAL then
            local hooks = {}
            for _, hook in ipairs(dbg.hooks()) do
                table_insert(hooks, hook.key)
            end
            core.log.info("alive hooks: ", cjson.encode(hooks))
            last_report_time = ts
        end
    end

    local ok, err = ngx.timer.at(delay, reload_hooks, delay, file)
    if not ok then
        core.log.error("failed to create the timer: ", err)
        running = false
    end
end

function _M.init(delay, file)
    if not running then
        file = file or "/var/run/apisix_inspect_hooks.lua"
        delay = delay or 3

        setup_hooks(file)

        local ok, err = ngx.timer.at(delay, reload_hooks, delay, file)
        if not ok then
            core.log.error("failed to create the timer: ", err)
            return
        end
        running = true
    end
end

function _M.destroy()
    stop = true
end

return _M
