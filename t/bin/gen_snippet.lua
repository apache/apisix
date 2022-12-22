#!/usr/bin/env luajit
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
-- this script generates Nginx configuration in the test
-- so we can test some features with test-nginx
local pkg_cpath_org = package.cpath
local pkg_path_org = package.path
local pkg_cpath = "deps/lib64/lua/5.1/?.so;deps/lib/lua/5.1/?.so;"
local pkg_path = "deps/share/lua/5.1/?.lua;"
-- modify the load path to load our dependencies
package.cpath = pkg_cpath .. pkg_cpath_org
package.path  = pkg_path .. pkg_path_org


local file = require("apisix.cli.file")
local schema = require("apisix.cli.schema")
local snippet = require("apisix.cli.snippet")
local util = require("apisix.cli.util")
local yaml_conf, err = file.read_yaml_conf("t/servroot")
if not yaml_conf then
    error(err)
end

if yaml_conf.deployment.role == "data_plane" and
    yaml_conf.deployment.config_provider == "yaml"
    or yaml_conf.deployment.config_provider == "xds" then
    return
end

local ok, err = schema.validate(yaml_conf)
if not ok then
    error(err)
end

local or_info, err = util.execute_cmd("openresty -V 2>&1")
if not or_info then
    error("failed to exec cmd \'openresty -V 2>&1\', err: " .. err)
end

local use_apisix_base = true
if not or_info:find("apisix-nginx-module", 1, true) then
    use_apisix_base = false
end

local res, err
if arg[1] == "conf_server" then
    res, err = snippet.generate_conf_server(
        {
            apisix_home = "t/servroot/",
            use_apisix_base = use_apisix_base,
        },
        yaml_conf)
end

if not res then
    error(err or "none")
end
print(res)
