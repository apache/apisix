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
    if old_plugin and type(old_plugin.destroy) == "function" then
        old_plugin.destroy()
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

    if type(plugin.schema) ~= "table" then
        core.log.error("invalid plugin [", name, "] schema field")
        return
    end

    if not plugin.schema.properties then
        plugin.schema.properties = {}
    end

    local properties = plugin.schema.properties
    local plugin_injected_schema = core.schema.plugin_injected_schema

    if plugin.schema['$comment'] ~= plugin_injected_schema['$comment'] then
        if properties.disable then
            core.log.error("invalid plugin [", name,
                           "]: found forbidden 'disable' field in the schema")
            return
        end

        properties.disable = plugin_injected_schema.disable
        plugin.schema['$comment'] = plugin_injected_schema['$comment']
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
        local plugins_conf = config.value
        for _, conf in ipairs(plugins_conf) do
            if conf.stream then
                core.table.insert(stream_plugin_names, conf.name)
            else
                core.table.insert(http_plugin_names, conf.name)
            end
        end
    end

    if ngx.config.subsystem == "http" then
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


local function trace_plugins_info_for_debug(plugins)
    if not (local_conf and local_conf.apisix.enable_debug) then
        return
    end

    local is_http = ngx.config.subsystem == "http"

    if not plugins then
        if is_http and not ngx.headers_sent then
            core.response.add_header("Apisix-Plugins", "no plugin")
        else
            core.log.warn("Apisix-Plugins: no plugin")
        end

        return
    end

    local t = {}
    for i = 1, #plugins, 2 do
        core.table.insert(t, plugins[i].name)
    end
    if is_http and not ngx.headers_sent then
        core.response.add_header("Apisix-Plugins", core.table.concat(t, ", "))
    else
        core.log.warn("Apisix-Plugins: ", core.table.concat(t, ", "))
    end
end


function _M.filter(user_route, plugins)
    local user_plugin_conf = user_route.value.plugins
    if user_plugin_conf == nil or
       core.table.nkeys(user_plugin_conf) == 0 then
        trace_plugins_info_for_debug(nil)
        -- when 'plugins' is given, always return 'plugins' itself instead
        -- of another one
        return plugins or core.empty_tab
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

    trace_plugins_info_for_debug(plugins)

    return plugins
end


function _M.stream_filter(user_route, plugins)
    plugins = plugins or core.table.new(#stream_local_plugins * 2, 0)
    local user_plugin_conf = user_route.value.plugins
    if user_plugin_conf == nil then
        trace_plugins_info_for_debug(nil)
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

    trace_plugins_info_for_debug(plugins)

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
        -- when route's upstream override service's upstream,
        -- the upstream.parent still point to the route
        new_conf.value.upstream_id = nil
        new_conf.has_domain = route_conf.has_domain
    end

    if route_conf.value.upstream_id then
        new_conf.value.upstream_id = route_conf.value.upstream_id
        new_conf.has_domain = route_conf.has_domain
    end

    if route_conf.value.script then
        new_conf.value.script = route_conf.value.script
    end

    if route_conf.value.name then
        new_conf.value.name = route_conf.value.name
    else
        new_conf.value.name = nil
    end

    -- core.log.info("merged conf : ", core.json.delay_encode(new_conf))
    return new_conf
end


function _M.merge_service_route(service_conf, route_conf)
    core.log.info("service conf: ", core.json.delay_encode(service_conf, true))
    core.log.info("  route conf: ", core.json.delay_encode(route_conf, true))

    local route_service_key = route_conf.value.id .. "#"
        .. route_conf.modifiedIndex .. "#" .. service_conf.modifiedIndex
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
            filter = function(item)
                -- we need to pass 'item' instead of plugins_conf because
                -- the latter one is nil at the first run
                _M.load(item)
            end,
        })
        if not plugins_conf then
            error("failed to create etcd instance for fetching /plugins : " .. err)
        end
    end
end


function _M.init_worker()
    -- some plugins need to be initialized in init* phases
    if ngx.config.subsystem == "http" then
        require("apisix.plugins.prometheus.exporter").init()
    end

    _M.load()

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


function _M.get_all(attrs)
    local plugins = {}

    if local_plugins_hash then
        for name, plugin_obj in pairs(local_plugins_hash) do
            plugins[name] = core.table.pick(plugin_obj, attrs)
        end
    end

    if stream_local_plugins_hash then
        for name, plugin_obj in pairs(stream_local_plugins_hash) do
            plugins[name] = core.table.pick(plugin_obj, attrs)
        end
    end

    return plugins
end


local function check_schema(plugins_conf, schema_type, skip_disabled_plugin)
    for name, plugin_conf in pairs(plugins_conf) do
        core.log.info("check plugin schema, name: ", name, ", configurations: ",
                      core.json.delay_encode(plugin_conf, true))
        if type(plugin_conf) ~= "table" then
            return false, "invalid plugin conf " ..
                core.json.encode(plugin_conf, true) ..
                " for plugin [" .. name .. "]"
        end

        local plugin_obj = local_plugins_hash[name]
        if not plugin_obj then
            if skip_disabled_plugin then
                goto CONTINUE
            else
                return false, "unknown plugin [" .. name .. "]"
            end
        end

        if plugin_obj.check_schema then
            local disable = plugin_conf.disable
            plugin_conf.disable = nil

            local ok, err = plugin_obj.check_schema(plugin_conf, schema_type)
            if not ok then
                return false, "failed to check the configuration of plugin "
                              .. name .. " err: " .. err
            end

            plugin_conf.disable = disable
        end

        ::CONTINUE::
    end

    return true
end
_M.check_schema = check_schema


local function stream_check_schema(plugins_conf, schema_type, skip_disabled_plugin)
    for name, plugin_conf in pairs(plugins_conf) do
        core.log.info("check stream plugin schema, name: ", name,
                      ": ", core.json.delay_encode(plugin_conf, true))
        if type(plugin_conf) ~= "table" then
            return false, "invalid plugin conf " ..
                core.json.encode(plugin_conf, true) ..
                " for plugin [" .. name .. "]"
        end

        local plugin_obj = stream_local_plugins_hash[name]
        if not plugin_obj then
            if skip_disabled_plugin then
                goto CONTINUE
            else
                return false, "unknown plugin [" .. name .. "]"
            end
        end

        if plugin_obj.check_schema then
            local disable = plugin_conf.disable
            plugin_conf.disable = nil

            local ok, err = plugin_obj.check_schema(plugin_conf, schema_type)
            if not ok then
                return false, "failed to check the configuration of "
                              .. "stream plugin [" .. name .. "]: " .. err
            end

            plugin_conf.disable = disable
        end

        ::CONTINUE::
    end

    return true
end
_M.stream_check_schema = stream_check_schema


function _M.plugin_checker(item, schema_type)
    if item.plugins then
        return check_schema(item.plugins, schema_type, true)
    end

    return true
end


function _M.stream_plugin_checker(item)
    if item.plugins then
        return stream_check_schema(item.plugins, nil, true)
    end

    return true
end


function _M.run_plugin(phase, plugins, api_ctx)
    api_ctx = api_ctx or ngx.ctx.api_ctx
    if not api_ctx then
        return
    end

    plugins = plugins or api_ctx.plugins
    if not plugins or #plugins == 0 then
        return api_ctx
    end

    if phase ~= "log"
        and phase ~= "header_filter"
        and phase ~= "body_filter"
    then
        for i = 1, #plugins, 2 do
            local phase_func = plugins[i][phase]
            if phase_func then
                local code, body = phase_func(plugins[i + 1], api_ctx)
                if code or body then
                    if code >= 400 then
                        core.log.warn(plugins[i].name, " exits with http status code ", code)
                    end

                    core.response.exit(code, body)
                end
            end
        end
        return api_ctx
    end

    for i = 1, #plugins, 2 do
        local phase_func = plugins[i][phase]
        if phase_func then
            phase_func(plugins[i + 1], api_ctx)
        end
    end

    return api_ctx
end


function _M.run_global_rules(api_ctx, global_rules, phase_name)
    if global_rules and global_rules.values
       and #global_rules.values > 0 then
        local orig_conf_type = api_ctx.conf_type
        local orig_conf_version = api_ctx.conf_version
        local orig_conf_id = api_ctx.conf_id

        if phase_name == nil then
            api_ctx.global_rules = global_rules
        end

        local plugins = core.tablepool.fetch("plugins", 32, 0)
        local values = global_rules.values
        for _, global_rule in config_util.iterate_values(values) do
            api_ctx.conf_type = "global_rule"
            api_ctx.conf_version = global_rule.modifiedIndex
            api_ctx.conf_id = global_rule.value.id

            core.table.clear(plugins)
            plugins = _M.filter(global_rule, plugins)
            if phase_name == nil then
                _M.run_plugin("rewrite", plugins, api_ctx)
                _M.run_plugin("access", plugins, api_ctx)
            else
                _M.run_plugin(phase_name, plugins, api_ctx)
            end
        end
        core.tablepool.release("plugins", plugins)

        api_ctx.conf_type = orig_conf_type
        api_ctx.conf_version = orig_conf_version
        api_ctx.conf_id = orig_conf_id
    end
end


return _M
