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
local require       = require
local core          = require("apisix.core")
local config_util   = require("apisix.core.config_util")
local pkg_loaded    = package.loaded
local sort_tab      = table.sort
local pcall         = pcall
local ipairs        = ipairs
local pairs         = pairs
local type          = type
local local_plugins = core.table.new(32, 0)
local ngx           = ngx
local tostring      = tostring
local error         = error
local local_plugins_hash    = core.table.new(0, 32)
local stream_local_plugins  = core.table.new(32, 0)
local stream_local_plugins_hash = core.table.new(0, 32)


local merged_route = core.lrucache.new({
    ttl = 300, count = 512
})
local local_conf


local _M = {
    version         = 0.3,

    load_times      = 0,
    plugins         = local_plugins,
    plugins_hash    = local_plugins_hash,

    stream_load_times= 0,
    stream_plugins  = stream_local_plugins,
    stream_plugins_hash = stream_local_plugins_hash,
}


local function plugin_attr(name)
    -- TODO: get attr from synchronized data
    local local_conf = core.config.local_conf()
    return core.table.try_read_attr(local_conf, "plugin_attr", name)
end
_M.plugin_attr = plugin_attr


local function sort_plugin(l, r)
    return l.priority > r.priority
end


local function unload_plugin(name, is_stream_plugin)
    local pkg_name = "apisix.plugins." .. name
    if is_stream_plugin then
        pkg_name = "apisix.stream.plugins." .. name
    end

    local old_plugin = pkg_loaded[pkg_name]
    if old_plugin and type(old_plugin.destory) == "function" then
        old_plugin.destory()
    end

    pkg_loaded[pkg_name] = nil
end


local function load_plugin(name, plugins_list, is_stream_plugin)
    local pkg_name = "apisix.plugins." .. name
    if is_stream_plugin then
        pkg_name = "apisix.stream.plugins." .. name
    end

    local ok, plugin = pcall(require, pkg_name)
    if not ok then
        core.log.error("failed to load plugin [", name, "] err: ", plugin)
        return
    end

    if not plugin.priority then
        core.log.error("invalid plugin [", name,
                        "], missing field: priority")
        return
    end

    if not plugin.version then
        core.log.error("invalid plugin [", name, "] missing field: version")
        return
    end

    if plugin.schema and plugin.schema.type == "object" then
        if not plugin.schema.properties or
           core.table.nkeys(plugin.schema.properties) == 0
        then
            plugin.schema.properties = core.schema.plugin_disable_schema
        end
    end

    plugin.name = name
    plugin.attr = plugin_attr(name)
    core.table.insert(plugins_list, plugin)

    if plugin.init then
        plugin.init()
    end

    return
end


local function plugins_eq(old, new)
    local eq = core.table.set_eq(old, new)
    if not eq then
        core.log.info("plugin list changed")
        return false
    end

    for name, plugin in pairs(old) do
        eq = core.table.deep_eq(plugin.attr, plugin_attr(name))
        if not eq then
            core.log.info("plugin_attr of ", name, " changed")
            return false
        end
    end

    return true
end


local function load(plugin_names)
    local processed = {}
    for _, name in ipairs(plugin_names) do
        if processed[name] == nil then
            processed[name] = true
        end
    end

    -- the same configure may be synchronized more than one
    if plugins_eq(local_plugins_hash, processed) then
        core.log.info("plugins not changed")
        return true
    end

    core.log.warn("new plugins: ", core.json.delay_encode(processed))

    for name in pairs(local_plugins_hash) do
        unload_plugin(name)
    end

    core.table.clear(local_plugins)
    core.table.clear(local_plugins_hash)

    for name in pairs(processed) do
        load_plugin(name, local_plugins)
    end

    -- sort by plugin's priority
    if #local_plugins > 1 then
        sort_tab(local_plugins, sort_plugin)
    end

    for i, plugin in ipairs(local_plugins) do
        local_plugins_hash[plugin.name] = plugin
        if local_conf and local_conf.apisix
           and local_conf.apisix.enable_debug then
            core.log.warn("loaded plugin and sort by priority:",
                          " ", plugin.priority,
                          " name: ", plugin.name)
        end
    end

    _M.load_times = _M.load_times + 1
    core.log.info("load plugin times: ", _M.load_times)
    return true
end


local function load_stream(plugin_names)
    local processed = {}
    for _, name in ipairs(plugin_names) do
        if processed[name] == nil then
            processed[name] = true
        end
    end

    -- the same configure may be synchronized more than one
    if plugins_eq(stream_local_plugins_hash, processed) then
        core.log.info("plugins not changed")
        return true
    end

    core.log.warn("new plugins: ", core.json.delay_encode(processed))

    for name in pairs(stream_local_plugins_hash) do
        unload_plugin(name, true)
    end

    core.table.clear(stream_local_plugins)
    core.table.clear(stream_local_plugins_hash)

    for name in pairs(processed) do
        load_plugin(name, stream_local_plugins, true)
    end

    -- sort by plugin's priority
    if #stream_local_plugins > 1 then
        sort_tab(stream_local_plugins, sort_plugin)
    end

    for i, plugin in ipairs(stream_local_plugins) do
        stream_local_plugins_hash[plugin.name] = plugin
        if local_conf and local_conf.apisix
           and local_conf.apisix.enable_debug then
            core.log.warn("loaded stream plugin and sort by priority:",
                          " ", plugin.priority,
                          " name: ", plugin.name)
        end
    end

    _M.stream_load_times = _M.stream_load_times + 1
    core.log.info("stream plugins: ",
                  core.json.delay_encode(stream_local_plugins, true))
    core.log.info("load stream plugin times: ", _M.stream_load_times)
    return true
end


function _M.load(config)
    local http_plugin_names
    local stream_plugin_names

    if not config then
        -- called during starting or hot reload in admin
        local_conf = core.config.local_conf(true)
        http_plugin_names = local_conf.plugins
        stream_plugin_names = local_conf.stream_plugins
    else
        -- called during synchronizing plugin data
        http_plugin_names = {}
        stream_plugin_names = {}
        for _, conf_value in config_util.iterate_values(config.values) do
            local plugins_conf = conf_value.value
            for _, conf in ipairs(plugins_conf) do
                if conf.stream then
                    core.table.insert(stream_plugin_names, conf.name)
                else
                    core.table.insert(http_plugin_names, conf.name)
                end
            end
        end
    end

    if ngx.config.subsystem == "http"then
        if not http_plugin_names then
            core.log.error("failed to read plugin list from local file")
        else
            local ok, err = load(http_plugin_names)
            if not ok then
                core.log.error("failed to load plugins: ", err)
            end
        end
    end

    if not stream_plugin_names then
        core.log.warn("failed to read stream plugin list from local file")
    else
        local ok, err = load_stream(stream_plugin_names)
        if not ok then
            core.log.error("failed to load stream plugins: ", err)
        end
    end

    -- for test
    return local_plugins
end


function _M.filter(user_route, plugins)
    local user_plugin_conf = user_route.value.plugins
    if user_plugin_conf == nil or
       core.table.nkeys(user_plugin_conf) == 0 then
        if local_conf and local_conf.apisix.enable_debug then
            core.response.set_header("Apisix-Plugins", "no plugin")
        end
        return core.empty_tab
    end

    plugins = plugins or core.tablepool.fetch("plugins", 32, 0)
    for _, plugin_obj in ipairs(local_plugins) do
        local name = plugin_obj.name
        local plugin_conf = user_plugin_conf[name]

        if type(plugin_conf) == "table" and not plugin_conf.disable then
            core.table.insert(plugins, plugin_obj)
            core.table.insert(plugins, plugin_conf)
        end
    end

    if local_conf.apisix.enable_debug then
        local t = {}
        for i = 1, #plugins, 2 do
            core.table.insert(t, plugins[i].name)
        end
        core.response.set_header("Apisix-Plugins", core.table.concat(t, ", "))
    end

    return plugins
end


function _M.stream_filter(user_route, plugins)
    plugins = plugins or core.table.new(#stream_local_plugins * 2, 0)
    local user_plugin_conf = user_route.value.plugins
    if user_plugin_conf == nil then
        if local_conf and local_conf.apisix.enable_debug then
            core.response.set_header("Apisix-Plugins", "no plugin")
        end
        return plugins
    end

    for _, plugin_obj in ipairs(stream_local_plugins) do
        local name = plugin_obj.name
        local plugin_conf = user_plugin_conf[name]

        if type(plugin_conf) == "table" and not plugin_conf.disable then
            core.table.insert(plugins, plugin_obj)
            core.table.insert(plugins, plugin_conf)
        end
    end

    if local_conf.apisix.enable_debug then
        local t = {}
        for i = 1, #plugins, 2 do
            core.table.insert(t, plugins[i].name)
        end
        core.response.set_header("Apisix-Plugins", core.table.concat(t, ", "))
    end

    return plugins
end


local function merge_service_route(service_conf, route_conf)
    local new_conf = core.table.deepcopy(service_conf)
    new_conf.value.service_id = new_conf.value.id
    new_conf.value.id = route_conf.value.id
    new_conf.modifiedIndex = route_conf.modifiedIndex

    if route_conf.value.plugins then
        for name, conf in pairs(route_conf.value.plugins) do
            if not new_conf.value.plugins then
                new_conf.value.plugins = {}
            end

            new_conf.value.plugins[name] = conf
        end
    end

    local route_upstream = route_conf.value.upstream
    if route_upstream then
        new_conf.value.upstream = route_upstream

        if route_upstream.checks then
            route_upstream.parent = route_conf
        end

        new_conf.value.upstream_id = nil
        new_conf.has_domain = route_conf.has_domain
    end

    if route_conf.value.upstream_id then
        new_conf.value.upstream_id = route_conf.value.upstream_id
        new_conf.has_domain = route_conf.has_domain
    end

    -- core.log.info("merged conf : ", core.json.delay_encode(new_conf))
    return new_conf
end


function _M.merge_service_route(service_conf, route_conf)
    core.log.info("service conf: ", core.json.delay_encode(service_conf))
    core.log.info("  route conf: ", core.json.delay_encode(route_conf))

    local route_service_key = route_conf.modifiedIndex .. "#" .. service_conf.modifiedIndex
    return merged_route(route_service_key, service_conf,
                        merge_service_route,
                        service_conf, route_conf)
end


local function merge_consumer_route(route_conf, consumer_conf)
    if not consumer_conf.plugins or
       core.table.nkeys(consumer_conf.plugins) == 0
    then
        core.log.info("consumer no plugins")
        return route_conf
    end

    local new_route_conf = core.table.deepcopy(route_conf)
    for name, conf in pairs(consumer_conf.plugins) do
        if not new_route_conf.value.plugins then
            new_route_conf.value.plugins = {}
        end

        new_route_conf.value.plugins[name] = conf
    end

    core.log.info("merged conf : ", core.json.delay_encode(new_route_conf))
    return new_route_conf
end


function _M.merge_consumer_route(route_conf, consumer_conf, api_ctx)
    core.log.info("route conf: ", core.json.delay_encode(route_conf))
    core.log.info("consumer conf: ", core.json.delay_encode(consumer_conf))

    local flag = tostring(route_conf) .. tostring(consumer_conf)
    local new_conf = merged_route(flag, nil,
                        merge_consumer_route, route_conf, consumer_conf)

    api_ctx.conf_type = api_ctx.conf_type .. "&consumer"
    api_ctx.conf_version = api_ctx.conf_version .. "&" ..
                           api_ctx.consumer_ver
    api_ctx.conf_id = api_ctx.conf_id .. "&" .. api_ctx.consumer_name

    return new_conf, new_conf ~= route_conf
end


local init_plugins_syncer
do
    local plugins_conf

    function init_plugins_syncer()
        local err
        plugins_conf, err = core.config.new("/plugins", {
            automatic = true,
            item_schema = core.schema.plugins,
            single_item = true,
            filter = function()
                _M.load(plugins_conf)
            end,
        })
        if not plugins_conf then
            error("failed to create etcd instance for fetching /plugins : " .. err)
        end
    end
end


function _M.init_worker()
    _M.load()

    -- some plugins need to be initialized in init* phases
    if ngx.config.subsystem == "http"then
        require("apisix.plugins.prometheus.exporter").init()
    end

    if local_conf and not local_conf.apisix.enable_admin then
        init_plugins_syncer()
    end

    local plugin_metadatas, err = core.config.new("/plugin_metadata",
        {automatic = true}
    )
    if not plugin_metadatas then
        error("failed to create etcd instance for fetching /plugin_metadatas : "
              .. err)
    end

    _M.plugin_metadatas = plugin_metadatas
end


function _M.plugin_metadata(name)
    return _M.plugin_metadatas:get(name)
end


function _M.get(name)
    return local_plugins_hash and local_plugins_hash[name]
end


return _M
