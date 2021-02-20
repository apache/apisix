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
local core = require("apisix.core")
local plugin_checker = require("apisix.plugin").plugin_checker
local pairs = pairs
local error = error


local plugin_configs


local _M = {
}


function _M.init_worker()
    local err
    plugin_configs, err = core.config.new("/plugin_configs", {
        automatic = true,
        checker = plugin_checker,
    })
    if not plugin_configs then
        error("failed to sync /plugin_configs: " .. err)
    end
end


function _M.get(id)
    return plugin_configs:get(id)
end


function _M.merge(route_conf, plugin_config)
    if route_conf.prev_plugin_config_ver == plugin_config.modifiedIndex then
        return route_conf
    end

    if not route_conf.value.plugins then
        route_conf.value.plugins = {}
    elseif not route_conf.orig_plugins then
        route_conf.orig_plugins = route_conf.value.plugins
        route_conf.value.plugins = core.table.clone(route_conf.value.plugins)
    end

    for name, value in pairs(plugin_config.value.plugins) do
        route_conf.value.plugins[name] = value
    end

    route_conf.update_count = route_conf.update_count + 1
    route_conf.modifiedIndex = route_conf.orig_modifiedIndex .. "#" .. route_conf.update_count
    route_conf.prev_plugin_config_ver = plugin_config.modifiedIndex

    return route_conf
end


return _M
