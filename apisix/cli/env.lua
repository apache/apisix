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

local require = require
local util = require("apisix.cli.util")

local pcall = pcall
local error = error
local exit = os.exit
local stderr = io.stderr
local str_find = string.find
local arg = arg
local package = package


return function (apisix_home, pkg_cpath_org, pkg_path_org)
    -- only for developer, use current folder as working space
    local is_root_path = false
    local script_path = arg[0]
    if script_path:sub(1, 2) == './' then
        apisix_home = util.trim(util.execute_cmd("pwd"))
        if not apisix_home then
            error("failed to fetch current path")
        end

        if str_find(apisix_home .. "/", '/root/', nil, true) == 1 then
            is_root_path = true
        end

        local pkg_cpath = apisix_home .. "/deps/lib64/lua/5.1/?.so;"
                          .. apisix_home .. "/deps/lib/lua/5.1/?.so;"

        local pkg_path = apisix_home .. "/?/init.lua;"
                         .. apisix_home .. "/deps/share/lua/5.1/?/init.lua;"
                         .. apisix_home .. "/deps/share/lua/5.1/?.lua;;"

        package.cpath = pkg_cpath .. package.cpath
        package.path  = pkg_path .. package.path
    end

    do
        -- skip luajit environment
        local ok = pcall(require, "table.new")
        if not ok then
            local ok, json = pcall(require, "cjson")
            if ok and json then
                stderr:write("please remove the cjson library in Lua, it may "
                            .. "conflict with the cjson library in openresty. "
                            .. "\n luarocks remove cjson\n")
                exit(1)
            end
        end
    end

    local openresty_args = [[openresty -p ]] .. apisix_home .. [[ -c ]]
                           .. apisix_home .. [[/conf/nginx.conf]]

    local min_etcd_version = "3.4.0"

    return {
        apisix_home = apisix_home,
        is_root_path = is_root_path,
        openresty_args = openresty_args,
        pkg_cpath_org = pkg_cpath_org,
        pkg_path_org = pkg_path_org,
        min_etcd_version = min_etcd_version,
    }
end
