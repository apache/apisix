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
local is_http = ngx.config.subsystem == "http"
local core = require("apisix.core")
local config_local = require("apisix.core.config_local")
local process
if is_http then
    process = require "ngx.process"
end
local pl_path = require("pl.path")


local _M = {}


do
    local path
    function _M.get_path()
        if not path then
            local local_conf = config_local.local_conf()
            if local_conf then
                local test_path =
                    core.table.try_read_attr(local_conf, "ext-plugin", "path_for_test")
                if test_path then
                    path = "unix:" .. test_path
                end
            end

            if not path then
                local sock = "./conf/apisix-" .. process.get_master_pid() .. ".sock"
                path = "unix:" .. pl_path.abspath(sock)
            end
        end

        return path
    end
end


function _M.get_conf_token_cache_time()
    return 3600
end


return _M
