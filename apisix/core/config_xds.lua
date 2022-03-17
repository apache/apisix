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
local io                = io
local io_open           = io.open
local io_close          = io.close
local package           = package
local new_tab           = base.new_tab
local ffi               = require ("ffi")
local C                 = ffi.C
local router_config     = ngx.shared["router-config"]
local ngx_re_match      = ngx.re.match
local ngx_re_gmatch     = ngx.re.gmatch

local xds_lib_name = "libxds.so"


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
        error("can not load Amesh library, tried paths: " ..
              table.concat(tried_paths, '\r\n', 1, #tried_paths))
    end

    local router_zone = C.ngx_http_lua_ffi_shdict_udata_to_zone(router_config[1])
    local router_shd_cdata = ffi.cast("void*", router_zone)
    xdsagent.initial(router_shd_cdata)
end



function _M.init_worker()
    if process.type() == "privileged agent" then
        load_libxds(xds_lib_name)
    end

    return true
end


return _M
