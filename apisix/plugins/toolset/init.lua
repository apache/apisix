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
local pairs = pairs
local core = require("apisix.core")
local ngx = ngx
local cache = core.table.new(0, 32)
local stop_timer = false
local load, unload = "load", "unload"
local package = package
local pcall = pcall
local require = require
local string = string

local _M = {
  version = 0.1,
  priority = 22901,
  name = "toolset",
  schema = {},
  scope = "global",
}


local function get_plugin_config()
  -- clear cache to reload
  package.loaded["apisix.plugins.toolset.config"] = nil
  local loaded, plugins_config = pcall(require, "apisix.plugins.toolset.config")
  if loaded and plugins_config == true then
    core.log.warn("empty plugin config file")
    return nil
  end
  if not loaded then
    core.log.error("failed to load plugin config: ", plugins_config)
    return nil
  end
  return plugins_config
end


local function is_config_changed(plugin_name, plugin_config)
  if core.table.deep_eq(cache[plugin_name], plugin_config) then
    return false
  end
  return true
end


local function is_config_empty(plugin_config)
  return plugin_config == nil or core.table.deep_eq(plugin_config, {})
end


local function perform_operation_for_plugin(plugin_name, plugin_config, operation)
  if operation == load then
    local loaded, plugin = pcall(require, "apisix.plugins.toolset.src."
                           .. string.gsub(plugin_name, "_", "-"))
    if not loaded then
      core.log.warn("could not load plugin because it was not found: ", plugin_name)
      return
    end
    core.log.warn("initializing sub plugin for toolset plugin: ", plugin_name)
    plugin.init()
    cache[plugin_name] = plugin_config
  elseif operation == unload then
    local loaded, plugin = pcall(require, "apisix.plugins.toolset.src." ..
                                 string.gsub(plugin_name, "_", "-"))
    if not loaded then
      core.log.warn("could not unload plugin because it was not found: ", plugin_name)
      return
    end
    core.log.warn("destroying sub plugin for toolset plugin: ", plugin_name)
    plugin.destroy()
    cache[plugin_name] = nil
  end
end


local function sync()
  core.log.debug("syncing toolset plugin")
  local plugin_configs = get_plugin_config()
  local processed_plugins = {}
  if plugin_configs then
    for plugin_name, plugin_config in pairs(plugin_configs) do
      processed_plugins[plugin_name] = true
      -- checks if the config is different from cache
      if is_config_changed(plugin_name, plugin_config) then
          if is_config_empty(plugin_config) then
            -- allow executing even with empty config.
            -- Assuming the plugin will run with default values
            core.log.warn("empty config found for ", plugin_name,".Running with default values")
          end
          core.log.warn("config changed. reloading plugin: ", plugin_name)
          local ok, err = pcall(perform_operation_for_plugin, plugin_name, plugin_config, load)
          if not ok then
            core.log.error("toolset plugin load raised: ", err)
          end
      end
    end
  end

  for plugin_name, plugin_config in pairs(cache) do
    if not processed_plugins[plugin_name] then
      core.log.warn("plugin config unloaded: ", plugin_name)
      local ok, err = pcall(perform_operation_for_plugin, plugin_name, plugin_config, unload)
      if not ok then
        core.log.error("toolset plugin unload raised: ", err)
      end
    end
  end
  if not stop_timer then
    local ok, err = ngx.timer.at(1, sync)
    if not ok then
      core.log.error("failed to create timer for running toolset ", err)
    end
  end
end


function _M.init()
    core.log.info("initializing toolset plugin")
    local plugins_config = get_plugin_config()
    if plugins_config then
      for plugin_name, plugin_config in pairs(plugins_config) do
        if is_config_empty(plugin_config) then
          -- allow executing even with empty config.
          -- Assuming the plugin will run with default values
          core.log.warn("empty config found for ", plugin_name,".Running with default values")
        end
        perform_operation_for_plugin(plugin_name, plugin_config, load)
      end
    end
    ngx.timer.at(1, sync)
end


function _M.destroy()
  local plugin_configs = get_plugin_config()
  if plugin_configs then
    for plugin_name, plugin_config in pairs(plugin_configs) do
      perform_operation_for_plugin(plugin_name, plugin_config, unload)
    end

  end
  for plugin_name, plugin_config in pairs(cache) do
    perform_operation_for_plugin(plugin_name, plugin_config, unload)
  end

  stop_timer = true
end

return _M
