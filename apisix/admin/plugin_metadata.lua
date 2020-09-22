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

local _M = {
}


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

    local schema = plugin_object.metadata_schema
    if not schema then
        return nil, {error_msg = "no metadata schema for plugin " .. plugin_name}
    end

    if not conf then
        return nil, {error_msg = "missing configurations"}
    end

    core.log.info("schema: ", core.json.delay_encode(schema))
    core.log.info("conf  : ", core.json.delay_encode(conf))
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return nil, {error_msg = "invalid configuration: " .. err}
    end

    return plugin_name
end


function _M.put(plugin_name, conf)
    local plugin_name, err = check_conf(plugin_name, conf)
    if not plugin_name then
        return 400, err
    end

    local key = "/plugin_metadata/" .. plugin_name
    core.log.info("key: ", key)
    local res, err = core.etcd.set(key, conf)
    if not res then
        core.log.error("failed to put plugin metadata[", key, "]: ", err)
        return 500, {error_msg = err}
    end

    return res.status, res.body
end


function _M.get(key)
    local path = "/plugin_metadata"
    if key then
        path = path .. "/" .. key
    end

    local res, err = core.etcd.get(path)
    if not res then
        core.log.error("failed to get metadata[", key, "]: ", err)
        return 500, {error_msg = err}
    end

    return res.status, res.body
end


function _M.post(key, conf)
    return 400, {error_msg = "not support `POST` method for metadata"}
end


function _M.delete(key)
    if not key then
        return 400, {error_msg = "missing metadata key"}
    end

    local key = "/plugin_metadata/" .. key
    local res, err = core.etcd.delete(key)
    if not res then
        core.log.error("failed to delete metadata[", key, "]: ", err)
        return 500, {error_msg = err}
    end

    return res.status, res.body
end


return _M
