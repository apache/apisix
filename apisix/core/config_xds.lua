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

--- Get configuration form ngx.shared.DICT.
--
-- @module core.config_xds

local base              = require("resty.core.base")
local config_local      = require("apisix.core.config_local")
local table             = table
local error             = error
local is_http           = ngx.config.subsystem == "http"
local string            = string
local io                = io
local package           = package
local new_tab           = base.new_tab
local ngx_timer_at      = ngx.timer.at
local ffi               = require ("ffi")
local C                 = ffi.C
local router_config     = ngx.shared["router-config"]

local process
if is_http then
    process = require("ngx.process")
end


ffi.cdef[[
extern void initial(void* router_zone_ptr);
]]


local _M = {
    version = 0.1,
    local_conf = config_local.local_conf,
}


-- todo: refactor this function in chash.lua and radixtree.lua
local function load_shared_lib(lib_name)
    local string_gmatch = string.gmatch
    local string_match = string.match
    local io_open = io.open
    local io_close = io.close

    local cpath = package.cpath
    local tried_paths = new_tab(32, 0)
    local i = 1

    for k, _ in string_gmatch(cpath, "[^;]+") do
        local fpath = string_match(k, "(.*/)")
        fpath = fpath .. lib_name

        local f = io_open(fpath)
        if f ~= nil then
            io_close(f)
            return ffi.load(fpath)
        end
        tried_paths[i] = fpath
        i = i + 1
    end

    return nil, tried_paths
end


local function load_libamesh(lib_name)
    local ameshagent, tried_paths = load_shared_lib(lib_name)

    if not ameshagent then
        tried_paths[#tried_paths + 1] = 'tried above paths but can not load ' .. lib_name
        error("can not load Amesh library, tried paths: " ..
              table.concat(tried_paths, '\r\n', 1, #tried_paths))
    end

    local router_zone = C.ngx_http_lua_ffi_shdict_udata_to_zone(router_config[1])
    local router_shd_cdata = ffi.cast("void*", router_zone)
    ameshagent.initial(router_shd_cdata)
end



function _M.init_worker()
    local lib_name = "libamesh.so"

    if process.type() == "privileged agent" then
        load_libamesh(lib_name)
    end

    return true
end


return _M
