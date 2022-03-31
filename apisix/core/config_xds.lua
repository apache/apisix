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

--- Get configuration form ngx.shared.DICT
--
-- @module core.config_xds

local config_local      = require("apisix.core.config_local")
local string            = require("apisix.core.string")
local log               = require("apisix.core.log")
local json              = require("apisix.core.json")
local ngx_sleep         = require("apisix.core.utils").sleep
local check_schema      = require("apisix.core.schema").check
local new_tab           = require("table.new")
local table             = table
local insert_tab        = table.insert
local error             = error
local is_http           = ngx.config.subsystem == "http"
local io                = io
local io_open           = io.open
local io_close          = io.close
local package           = package
local ffi               = require ("ffi")
local C                 = ffi.C
local config            = ngx.shared["xds-config"]
local conf_ver          = ngx.shared["xds-conf-version"]
local ngx_re_match      = ngx.re.match
local ngx_re_gmatch     = ngx.re.gmatch
local ngx_timer_every   = ngx.timer.every
local ngx_timer_at      = ngx.timer.at
local exiting           = ngx.worker.exiting
local ngx_time          = ngx.time
local ipairs            = ipairs
local type              = type
local sub_str           = string.sub

local xds_lib_name      = "libxds.so"

local created_obj       = {}

local process
if is_http then
    process = require("ngx.process")
end

local latest_version


ffi.cdef[[
extern void initial(void* config_zone, void* version_zone);
]]


local _M = {
    version = 0.1,
    local_conf = config_local.local_conf,
}


local mt = {
    __index = _M,
    __tostring = function(self)
        return " xds key: " .. self.key
    end
}


-- todo: refactor this function in chash.lua and radixtree.lua
local function load_shared_lib(lib_name)
    local cpath = package.cpath
    local tried_paths = new_tab(32, 0)
    local i = 1

    local iter, err = ngx_re_gmatch(cpath, "[^;]+", "jo")
    if not iter then
        error("failed to gmatch: " .. err)
    end

    while true do
        local it = iter()
        local fpath
        fpath, err = ngx_re_match(it[0], "(.*/)",  "jo")
        if err then
            error("failed to match: " .. err)
        end
        local spath = fpath[0] .. lib_name

        local f = io_open(spath)
        if f ~= nil then
            io_close(f)
            return ffi.load(spath)
        end
        tried_paths[i] = spath
        i = i + 1

        if not it then
            break
        end
    end

    return nil, tried_paths
end


local function load_libxds(lib_name)
    local xdsagent, tried_paths = load_shared_lib(lib_name)

    if not xdsagent then
        tried_paths[#tried_paths + 1] = 'tried above paths but can not load ' .. lib_name
        error("can not load xds library, tried paths: " ..
              table.concat(tried_paths, '\r\n', 1, #tried_paths))
    end

    local config_zone = C.ngx_http_lua_ffi_shdict_udata_to_zone(config[1])
    local config_shd_cdata = ffi.cast("void*", config_zone)

    local conf_ver_zone = C.ngx_http_lua_ffi_shdict_udata_to_zone(conf_ver[1])
    local conf_ver_shd_cdata = ffi.cast("void*", conf_ver_zone)

    xdsagent.initial(config_shd_cdata, conf_ver_shd_cdata)
end



local function sync_data(self)
    if not latest_version then
        return false, "wait for more time"
    end

    if self.conf_version == latest_version then
        return true
    end

    local keys = config:get_keys(0)

    self.values = new_tab(8, 0)

    if keys and #keys > 0 then
        for _, key in ipairs(keys) do
            if string.has_prefix(key, self.key) then
                local conf_str = config:get(key, 0)
                local conf, err = json.decode(conf_str)
                if not conf then
                    return false, "decode the conf of [" .. key .. "] failed, err: " .. err
                end

                if not self.single_item and type(conf) ~= "table" then
                    return false, "invalid conf of [".. key .. "], conf: " .. conf
                                  .. ", it should be an object"
                end

                if conf and self.item_schema then
                    local ok, err = check_schema(self.item_schema, conf)
                    if not ok then
                        return false, "failed to check the conf of ["
                                      .. key .. "] err:" .. err
                    end

                    if self.checker then
                        local ok, err = self.checker(conf)
                        if not ok then
                            return false, "failed to check conf of ["
                                          .. key .. "] err:" .. err
                        end
                    end
                end

                if not conf.id then
                    conf.id = sub_str(key, #self.key + 2, #key + 1)
                end

                local conf_item = {value = conf, modifiedIndex = latest_version,
                                   key = key}

                insert_tab(self.values, conf_item)
            end
        end
    end

    self.conf_version = latest_version
    return true
end


local function _automatic_fetch(premature, self)
    if premature then
        return
    end

    local i = 0
    while not exiting() and self.running and i <= 32 do
        i = i + 1
        local ok, ok2, err = pcall(sync_data, self)
        if not ok then
            err = ok2
            log.error("failed to fetch data from xds: ",
                      err, ", ", tostring(self))
            ngx_sleep(3)
            break
        elseif not ok2 and err then
            -- todo: handler other error
            if err ~= "wait for more time" and self.last_err ~= err then
                log.error("failed to fetch data from xds, ", err, ", ", tostring(self))
            end

            if err ~= self.last_err then
                self.last_err = err
                self.last_err_time = ngx_time()
            else
                if ngx_time() - self.last_err_time >= 30 then
                    self.last_err = nil
                end
            end
            ngx_sleep(0.5)
        elseif not ok2 then
            ngx_sleep(0.05)
        else
            ngx_sleep(0.1)
        end
    end

    if not exiting() and self.running then
        ngx_timer_at(0, _automatic_fetch, self)
    end
end


local function fetch_version(premature)
    if premature then
        return
    end

    local version = conf_ver:get("version")

    if not version then
        return
    end

    if version ~= latest_version then
        latest_version = version
    end
end


function _M.new(key, opts)
    local automatic = opts and opts.automatic
    local item_schema = opts and opts.item_schema
    local filter_fun = opts and opts.filter
    local single_item = opts and opts.single_item
    local checker = opts and opts.checker

    if key then
        local local_conf = config_local.local_conf()
        if local_conf and local_conf.etcd and local_conf.etcd.prefix then
            key = local_conf.etcd.prefix .. key
        end
    end

    local obj = setmetatable({
        automatic = automatic,
        item_schema = item_schema,
        checker = checker,
        sync_times = 0,
        running = true,
        conf_version = 0,
        values = nil,
        routes_hash = nil,
        prev_index = nil,
        last_err = nil,
        last_err_time = nil,
        key = key,
        single_item = single_item,
        filter = filter_fun,
    }, mt)

    if automatic then
        if not key then
            return nil, "missing `key` argument"
        end

        -- blocking until xds completes initial configuration
        while true do
            fetch_version()
            if latest_version then
                break
            end
        end

        local ok, ok2, err = pcall(sync_data, obj)
        if not ok then
            err = ok2
        end

        if err then
            log.error("failed to fetch data from xds ",
                      err, ", ", key)
        end

        ngx_timer_at(0, _automatic_fetch, obj)
    end

    if key then
        created_obj[key] = obj
    end

    return obj
end



function _M.init_worker()
    if process.type() == "privileged agent" then
        load_libxds(xds_lib_name)
    end

    ngx_timer_every(1, fetch_version)

    return true
end


return _M
