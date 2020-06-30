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
local yaml         = require("tinyyaml")
local log          = require("apisix.core.log")
local json         = require("apisix.core.json")
local profile      = require("apisix.core.profile")
local process      = require("ngx.process")
local lfs          = require("lfs")
local io           = io
local ngx          = ngx
local re_find      = ngx.re.find
local type         = type
local pairs        = pairs
local require      = require
local setmetatable = setmetatable
local pcall        = pcall
local ipairs       = ipairs
local unpack       = unpack
local debug_yaml_path = profile:yaml_path("debug")
local debug_yaml
local debug_yaml_ctime


local _M = {version = 0.1}


local function read_debug_yaml()
    local attributes, err = lfs.attributes(debug_yaml_path)
    if not attributes then
        log.notice("failed to fetch ", debug_yaml_path, " attributes: ", err)
        return
    end

    -- log.info("change: ", json.encode(attributes))
    local last_change_time = attributes.change
    if debug_yaml_ctime == last_change_time then
        return
    end

    local f, err = io.open(debug_yaml_path, "r")
    if not f then
        log.error("failed to open file ", debug_yaml_path, " : ", err)
        return
    end

    local found_end_flag
    for i = 1, 10 do
        f:seek('end', -i)

        local end_flag = f:read("*a")
        -- log.info(i, " flag: ", end_flag)
        if re_find(end_flag, [[#END\s*]], "jo") then
            found_end_flag = true
            break
        end
    end

    if not found_end_flag then
        f:seek("set")
        local size = f:seek("end")
        f:close()

        if size > 8 then
            log.warn("missing valid end flag in file ", debug_yaml_path)
        end
        return
    end

    f:seek('set')
    local yaml_config = f:read("*a")
    f:close()

    local debug_yaml_new = yaml.parse(yaml_config)
    if not debug_yaml_new then
        log.error("failed to parse the content of file " .. debug_yaml_path)
        return
    end

    debug_yaml_new.hooks = debug_yaml_new.hooks or {}
    debug_yaml = debug_yaml_new
    debug_yaml_ctime = last_change_time
end


local sync_debug_hooks
do
    local pre_mtime
    local enabled_hooks = {}

local function apple_new_fun(module, fun_name, file_path, hook_conf)
    local log_level = hook_conf.log_level or "warn"

    if not module or type(module[fun_name]) ~= "function" then
        log.error("failed to find function [", fun_name,
                  "] in module:", file_path)
        return
    end

    local fun = module[fun_name]
    local fun_org
    if enabled_hooks[fun] then
        fun_org = enabled_hooks[fun].org
        enabled_hooks[fun] = nil
    else
        fun_org = fun
    end

    local t = {fun_org = fun_org}
    local mt = {}

    function mt.__call(self, ...)
        local arg = {...}
        if hook_conf.is_print_input_args then
            log[log_level]("call require(\"", file_path, "\").", fun_name,
                           "() args:", json.delay_encode(arg, true))
        end

        local ret = {self.fun_org(...)}
        if hook_conf.is_print_return_value then
            log[log_level]("call require(\"", file_path, "\").", fun_name,
                           "() return:", json.delay_encode(ret, true))
        end
        return unpack(ret)
    end

    setmetatable(t, mt)
    enabled_hooks[t] = {
        org = fun_org, new = t, mod = module,
        fun_name = fun_name
    }
    module[fun_name] = t
end


function sync_debug_hooks()
    if not debug_yaml_ctime or debug_yaml_ctime == pre_mtime then
        return
    end

    for _, hook in pairs(enabled_hooks) do
        local m = hook.mod
        local name = hook.fun_name
        m[name] = hook.org
    end

    enabled_hooks = {}

    local hook_conf = debug_yaml.hook_conf
    if not hook_conf.enable then
        pre_mtime = debug_yaml_ctime
        return
    end

    local hook_name = hook_conf.name or ""
    local hooks = debug_yaml[hook_name]
    if not hooks then
        pre_mtime = debug_yaml_ctime
        return
    end

    for file_path, fun_names in pairs(hooks) do
        local ok, module = pcall(require, file_path)
        if not ok then
            log.error("failed to load module [", file_path, "]: ", module)

        else
            for _, fun_name in ipairs(fun_names) do
                apple_new_fun(module, fun_name, file_path, hook_conf)
            end
        end
    end

    pre_mtime = debug_yaml_ctime
end

end --do


local function sync_debug_status(premature)
    if premature then
        return
    end

    read_debug_yaml()
    sync_debug_hooks()
end


function _M.init_worker()
    if process.type() ~= "worker" and process.type() ~= "single" then
        return
    end

    sync_debug_status()
    ngx.timer.every(1, sync_debug_status)
end


return _M
