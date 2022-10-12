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

--- Get configuration information.
--
-- @module core.config_local

local file   = require("apisix.cli.file")
local schema = require("apisix.cli.schema")
local error  = error


local _M = {}


local config_data


function _M.clear_cache()
    config_data = nil
end

---
-- Get the local config info.
-- The configuration information consists of two parts, user-defined configuration in
-- `conf/config.yaml` and default configuration in `conf/config-default.yaml`. The configuration
-- of the same name present in `conf/config.yaml` will overwrite `conf/config-default.yaml`.
-- The final full configuration is `conf/config.yaml` and the default configuration in
-- `conf/config-default.yaml` that is not overwritten.
--
-- @function core.config_local.local_conf
-- @treturn table The configuration information.
-- @usage
-- -- Given a config item in `conf/config.yaml`:
-- --
-- -- apisix:
-- --   ssl:
-- --     fallback_sni: "a.test2.com"
-- --
-- -- you can get the value of `fallback_sni` by:
-- local local_conf = core.config.local_conf()
-- local fallback_sni = core.table.try_read_attr(
--                        local_conf, "apisix", "ssl", "fallback_sni") -- "a.test2.com"
function _M.local_conf(force)
    if not force and config_data then
        return config_data
    end

    local default_conf, err = file.read_yaml_conf()
    if not default_conf then
        return nil, err
    end

    -- fill the default value by the schema
    local ok, err = schema.validate(default_conf)
    if not ok then
        error(err)
    end

    config_data = default_conf
    return config_data
end


return _M
