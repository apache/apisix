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
local pcall   = pcall
local require = require
local core    = require("apisix.core")
local resource = require("apisix.admin.resource")
local encrypt_conf = require("apisix.plugin").encrypt_conf

local injected_mark = "injected metadata_schema"


local function validate_plugin(name)
    local pkg_name = "apisix.plugins." .. name
    local ok, plugin_object = pcall(require, pkg_name)
    if ok then
        return true, plugin_object
    end

    pkg_name = "apisix.stream.plugins." .. name
    return pcall(require, pkg_name)
end


local function check_conf(plugin_name, conf)
    if not plugin_name then
        return nil, {error_msg = "missing plugin name"}
    end

    local ok, plugin_object = validate_plugin(plugin_name)
    if not ok then
        return nil, {error_msg = "invalid plugin name"}
    end

    if not plugin_object.metadata_schema then
        plugin_object.metadata_schema = {
            type = "object",
            ['$comment'] = injected_mark,
            properties = {},
        }
    end
    local schema = plugin_object.metadata_schema

    local ok, err
    if schema['$comment'] == injected_mark
      -- check_schema is not required. If missing, fallback to check schema directly
      or not plugin_object.check_schema
    then
        ok, err = core.schema.check(schema, conf)
    else
        ok, err = plugin_object.check_schema(conf, core.schema.TYPE_METADATA)
    end

    encrypt_conf(plugin_name, conf, core.schema.TYPE_METADATA)

    if not ok then
        return nil, {error_msg = "invalid configuration: " .. err}
    end

    return plugin_name
end


return resource.new({
    name = "plugin_metadata",
    kind = "plugin_metadata",
    schema = core.schema.plugin_metadata,
    checker = check_conf,
    unsupported_methods = {"post", "patch"}
})
