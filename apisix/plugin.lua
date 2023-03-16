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
local enable_debug  = require("apisix.debug").enable_debug
local wasm          = require("apisix.wasm")
local expr          = require("resty.expr.v1")
local apisix_ssl    = require("apisix.ssl")
local re_split      = require("ngx.re").split
local ngx           = ngx
local crc32         = ngx.crc32_short
local ngx_exit      = ngx.exit
local pkg_loaded    = package.loaded
local sort_tab      = table.sort
local pcall         = pcall
local ipairs        = ipairs
local pairs         = pairs
local type          = type
local local_plugins = core.table.new(32, 0)
local tostring      = tostring
local error         = error
local is_http       = ngx.config.subsystem == "http"
local local_plugins_hash    = core.table.new(0, 32)
local stream_local_plugins  = core.table.new(32, 0)
local stream_local_plugins_hash = core.table.new(0, 32)


local merged_route = core.lrucache.new({
    ttl = 300, count = 512
})
local expr_lrucache = core.lrucache.new({
    ttl = 300, count = 512
})
local local_conf
local check_plugin_metadata

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

local function custom_sort_plugin(l, r)
    return l._meta.priority > r._meta.priority
end

local function check_disable(plugin_conf)
    if not plugin_conf then
        return nil
    end

    if not plugin_conf._meta then
       return nil
    end

    if type(plugin_conf._meta) ~= "table" then
        return nil
    end

    return plugin_conf._meta.disable
end

local PLUGIN_TYPE_HTTP = 1
local PLUGIN_TYPE_STREAM = 2
local PLUGIN_TYPE_HTTP_WASM = 3
local function unload_plugin(name, plugin_type)
    if plugin_type == PLUGIN_TYPE_HTTP_WASM then
        return
    end

    local pkg_name = "apisix.plugins." .. name
    if plugin_type == PLUGIN_TYPE_STREAM then
        pkg_name = "apisix.stream.plugins." .. name
    end

    local old_plugin = pkg_loaded[pkg_name]
    if old_plugin and type(old_plugin.destroy) == "function" then
        old_plugin.destroy()
    end

    pkg_loaded[pkg_name] = nil
end


local function load_plugin(name, plugins_list, plugin_type)
    local ok, plugin
    if plugin_type == PLUGIN_TYPE_HTTP_WASM  then
        -- for wasm plugin, we pass the whole attrs instead of name
        ok, plugin = wasm.require(name)
        name = name.name
    else
        local pkg_name = "apisix.plugins." .. name
        if plugin_type == PLUGIN_TYPE_STREAM then
            pkg_name = "apisix.stream.plugins." .. name
        end

        ok, plugin = pcall(require, pkg_name)
    end

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
        if properties._meta then
            core.log.error("invalid plugin [", name,
                           "]: found forbidden '_meta' field in the schema")
            return
        end

        properties._meta = plugin_injected_schema._meta
        -- new injected fields should be added under `_meta`
        -- 1. so we won't break user's code when adding any new injected fields
        -- 2. the semantics is clear, especially in the doc and in the caller side

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


local function load(plugin_names, wasm_plugin_names)
    local processed = {}
    for _, name in ipairs(plugin_names) do
        if processed[name] == nil then
            processed[name] = true
        end
    end
    for _, attrs in ipairs(wasm_plugin_names) do
        if processed[attrs.name] == nil then
            processed[attrs.name] = attrs
        end
    end

    core.log.warn("new plugins: ", core.json.delay_encode(processed))

    for name, plugin in pairs(local_plugins_hash) do
        local ty = PLUGIN_TYPE_HTTP
        if plugin.type == "wasm" then
            ty = PLUGIN_TYPE_HTTP_WASM
        end
        unload_plugin(name, ty)
    end

    core.table.clear(local_plugins)
    core.table.clear(local_plugins_hash)

    for name, value in pairs(processed) do
        local ty = PLUGIN_TYPE_HTTP
        if type(value) == "table" then
            ty = PLUGIN_TYPE_HTTP_WASM
            name = value
        end
        load_plugin(name, local_plugins, ty)
    end

    -- sort by plugin's priority
    if #local_plugins > 1 then
        sort_tab(local_plugins, sort_plugin)
    end

    for i, plugin in ipairs(local_plugins) do
        local_plugins_hash[plugin.name] = plugin
        if enable_debug() then
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

    core.log.warn("new plugins: ", core.json.delay_encode(processed))

    for name in pairs(stream_local_plugins_hash) do
        unload_plugin(name, PLUGIN_TYPE_STREAM)
    end

    core.table.clear(stream_local_plugins)
    core.table.clear(stream_local_plugins_hash)

    for name in pairs(processed) do
        load_plugin(name, stream_local_plugins, PLUGIN_TYPE_STREAM)
    end

    -- sort by plugin's priority
    if #stream_local_plugins > 1 then
        sort_tab(stream_local_plugins, sort_plugin)
    end

    for i, plugin in ipairs(stream_local_plugins) do
        stream_local_plugins_hash[plugin.name] = plugin
        if enable_debug() then
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


local function get_plugin_names(config)
    local http_plugin_names
    local stream_plugin_names

    if not config then
        -- called during starting or hot reload in admin
        local err
        local_conf, err = core.config.local_conf(true)
        if not local_conf then
            -- the error is unrecoverable, so we need to raise it
            error("failed to load the configuration file: " .. err)
        end

        http_plugin_names = local_conf.plugins
        stream_plugin_names = local_conf.stream_plugins
    else
        -- called during synchronizing plugin data
        http_plugin_names = {}
        stream_plugin_names = {}
        local plugins_conf = config.value
        -- plugins_conf can be nil when another instance writes into etcd key "/apisix/plugins/"
        if not plugins_conf then
            return true
        end

        for _, conf in ipairs(plugins_conf) do
            if conf.stream then
                core.table.insert(stream_plugin_names, conf.name)
            else
                core.table.insert(http_plugin_names, conf.name)
            end
        end
    end

    return false, http_plugin_names, stream_plugin_names
end


function _M.load(config)
    local ignored, http_plugin_names, stream_plugin_names = get_plugin_names(config)
    if ignored then
        return local_plugins
    end

    if ngx.config.subsystem == "http" then
        if not http_plugin_names then
            core.log.error("failed to read plugin list from local file")
        else
            local wasm_plugin_names = {}
            if local_conf.wasm then
                wasm_plugin_names = local_conf.wasm.plugins
            end

            local ok, err = load(http_plugin_names, wasm_plugin_names)
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


function _M.exit_worker()
    for name, plugin in pairs(local_plugins_hash) do
        local ty = PLUGIN_TYPE_HTTP
        if plugin.type == "wasm" then
            ty = PLUGIN_TYPE_HTTP_WASM
        end
        unload_plugin(name, ty)
    end

    -- we need to load stream plugin so that we can check their schemas in
    -- Admin API. Maybe we can avoid calling `load` in this case? So that
    -- we don't need to call `destroy` too
    for name in pairs(stream_local_plugins_hash) do
        unload_plugin(name, PLUGIN_TYPE_STREAM)
    end
end


local function trace_plugins_info_for_debug(ctx, plugins)
    if not enable_debug() then
        return
    end

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
        if ctx then
            local debug_headers = ctx.debug_headers
            if not debug_headers then
                debug_headers = core.table.new(0, 5)
            end
            for i, v in ipairs(t) do
                debug_headers[v] = true
            end
            ctx.debug_headers = debug_headers
        end
    else
        core.log.warn("Apisix-Plugins: ", core.table.concat(t, ", "))
    end
end


local function meta_filter(ctx, plugin_name, plugin_conf)
    local filter = plugin_conf._meta and plugin_conf._meta.filter
    if not filter then
        return true
    end

    local match_cache_key =
        ctx.conf_type .. "#" .. ctx.conf_id .. "#"
            .. ctx.conf_version .. "#" .. plugin_name .. "#meta_filter_matched"
    if ctx[match_cache_key] ~= nil then
        return ctx[match_cache_key]
    end

    local ex, ok, err
    if ctx then
        ex, err = expr_lrucache(plugin_name .. ctx.conf_type .. ctx.conf_id,
                                 ctx.conf_version, expr.new, filter)
    else
        ex, err = expr.new(filter)
    end
    if not ex then
        core.log.warn("failed to get the 'vars' expression: ", err ,
                         " plugin_name: ", plugin_name)
        return true
    end
    ok, err = ex:eval(ctx.var)
    if err then
        core.log.warn("failed to run the 'vars' expression: ", err,
                         " plugin_name: ", plugin_name)
        return true
    end

    ctx[match_cache_key] = ok
    return ok
end


function _M.filter(ctx, conf, plugins, route_conf, phase)
    local user_plugin_conf = conf.value.plugins
    if user_plugin_conf == nil or
       core.table.nkeys(user_plugin_conf) == 0 then
        trace_plugins_info_for_debug(nil, nil)
        -- when 'plugins' is given, always return 'plugins' itself instead
        -- of another one
        return plugins or core.tablepool.fetch("plugins", 0, 0)
    end

    local custom_sort = false
    local route_plugin_conf = route_conf and route_conf.value.plugins
    plugins = plugins or core.tablepool.fetch("plugins", 32, 0)
    for _, plugin_obj in ipairs(local_plugins) do
        local name = plugin_obj.name
        local plugin_conf = user_plugin_conf[name]

        if type(plugin_conf) ~= "table" then
            goto continue
        end

        if not check_disable(plugin_conf) then
            if plugin_obj.run_policy == "prefer_route" and route_plugin_conf ~= nil then
                local plugin_conf_in_route = route_plugin_conf[name]
                local disable_in_route = check_disable(plugin_conf_in_route)
                if plugin_conf_in_route and not disable_in_route then
                    goto continue
                end
            end

            if plugin_conf._meta and plugin_conf._meta.priority then
                custom_sort = true
            end
            core.table.insert(plugins, plugin_obj)
            core.table.insert(plugins, plugin_conf)
        end

        ::continue::
    end

    trace_plugins_info_for_debug(ctx, plugins)

    if custom_sort then
        local tmp_plugin_objs = core.tablepool.fetch("tmp_plugin_objs", 0, #plugins / 2)
        local tmp_plugin_confs = core.tablepool.fetch("tmp_plugin_confs", #plugins / 2, 0)

        for i = 1, #plugins, 2 do
            local plugin_obj = plugins[i]
            local plugin_conf = plugins[i + 1]

            -- in the rewrite phase, the plugin executes in the following order:
            -- 1. execute the rewrite phase of the plugins on route(including the auth plugins)
            -- 2. merge plugins from consumer and route
            -- 3. execute the rewrite phase of the plugins on consumer(phase: rewrite_in_consumer)
            -- in this case, we need to skip the plugins that was already executed(step 1)
            if phase == "rewrite_in_consumer" and not plugin_conf._from_consumer then
                plugin_conf._skip_rewrite_in_consumer = true
            end

            tmp_plugin_objs[plugin_conf] = plugin_obj
            core.table.insert(tmp_plugin_confs, plugin_conf)

            if not plugin_conf._meta then
                plugin_conf._meta = core.table.new(0, 1)
                plugin_conf._meta.priority = plugin_obj.priority
            else
                if not plugin_conf._meta.priority then
                    plugin_conf._meta.priority = plugin_obj.priority
                end
            end
        end

        sort_tab(tmp_plugin_confs, custom_sort_plugin)

        local index
        for i = 1, #tmp_plugin_confs do
            index = i * 2 - 1
            local plugin_conf = tmp_plugin_confs[i]
            local plugin_obj = tmp_plugin_objs[plugin_conf]
            plugins[index] = plugin_obj
            plugins[index + 1] = plugin_conf
        end

        core.tablepool.release("tmp_plugin_objs", tmp_plugin_objs)
        core.tablepool.release("tmp_plugin_confs", tmp_plugin_confs)
    end

    return plugins
end


function _M.stream_filter(user_route, plugins)
    plugins = plugins or core.table.new(#stream_local_plugins * 2, 0)
    local user_plugin_conf = user_route.value.plugins
    if user_plugin_conf == nil then
        trace_plugins_info_for_debug(nil, nil)
        return plugins
    end

    for _, plugin_obj in ipairs(stream_local_plugins) do
        local name = plugin_obj.name
        local plugin_conf = user_plugin_conf[name]

        local disable = check_disable(plugin_conf)
        if type(plugin_conf) == "table" and not disable then
            core.table.insert(plugins, plugin_obj)
            core.table.insert(plugins, plugin_conf)
        end
    end

    trace_plugins_info_for_debug(nil, plugins)

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

    if route_conf.value.timeout then
        new_conf.value.timeout = route_conf.value.timeout
    end

    if route_conf.value.name then
        new_conf.value.name = route_conf.value.name
    else
        new_conf.value.name = nil
    end

    if route_conf.value.hosts then
        new_conf.value.hosts = route_conf.value.hosts
    end
    if not new_conf.value.hosts and route_conf.value.host then
        new_conf.value.host = route_conf.value.host
    end

    if route_conf.value.labels then
        new_conf.value.labels = route_conf.value.labels
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


local function merge_consumer_route(route_conf, consumer_conf, consumer_group_conf)
    if not consumer_conf.plugins or
       core.table.nkeys(consumer_conf.plugins) == 0
    then
        core.log.info("consumer no plugins")
        return route_conf
    end

    local new_route_conf = core.table.deepcopy(route_conf)

    if consumer_group_conf then
        for name, conf in pairs(consumer_group_conf.value.plugins) do
            if not new_route_conf.value.plugins then
                new_route_conf.value.plugins = {}
            end

            if new_route_conf.value.plugins[name] == nil then
                conf._from_consumer = true
            end
            new_route_conf.value.plugins[name] = conf
        end
    end

    for name, conf in pairs(consumer_conf.plugins) do
        if not new_route_conf.value.plugins then
            new_route_conf.value.plugins = {}
        end

        if new_route_conf.value.plugins[name] == nil then
            conf._from_consumer = true
        end
        new_route_conf.value.plugins[name] = conf
    end

    core.log.info("merged conf : ", core.json.delay_encode(new_route_conf))
    return new_route_conf
end


function _M.merge_consumer_route(route_conf, consumer_conf, consumer_group_conf, api_ctx)
    core.log.info("route conf: ", core.json.delay_encode(route_conf))
    core.log.info("consumer conf: ", core.json.delay_encode(consumer_conf))
    core.log.info("consumer group conf: ", core.json.delay_encode(consumer_group_conf))

    local flag = route_conf.value.id .. "#" .. route_conf.modifiedIndex
                 .. "#" .. consumer_conf.id .. "#" .. consumer_conf.modifiedIndex

    if consumer_group_conf then
        flag = flag .. "#" .. consumer_group_conf.value.id
            .. "#" .. consumer_group_conf.modifiedIndex
    end

    local new_conf = merged_route(flag, api_ctx.conf_version,
                        merge_consumer_route, route_conf, consumer_conf, consumer_group_conf)

    api_ctx.conf_type = api_ctx.conf_type .. "&consumer"
    api_ctx.conf_version = api_ctx.conf_version .. "&" ..
                           api_ctx.consumer_ver
    api_ctx.conf_id = api_ctx.conf_id .. "&" .. api_ctx.consumer_name

    if consumer_group_conf then
        api_ctx.conf_type = api_ctx.conf_type .. "&consumer_group"
        api_ctx.conf_version = api_ctx.conf_version .. "&" .. consumer_group_conf.modifiedIndex
        api_ctx.conf_id = api_ctx.conf_id .. "&" .. consumer_group_conf.value.id
    end

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
    local _, http_plugin_names, stream_plugin_names = get_plugin_names()

    -- some plugins need to be initialized in init* phases
    if is_http and core.table.array_find(http_plugin_names, "prometheus") then
        local prometheus_enabled_in_stream =
            core.table.array_find(stream_plugin_names, "prometheus")
        require("apisix.plugins.prometheus.exporter").http_init(prometheus_enabled_in_stream)
    elseif not is_http and core.table.array_find(stream_plugin_names, "prometheus") then
        require("apisix.plugins.prometheus.exporter").stream_init()
    end

    -- someone's plugin needs to be initialized after prometheus
    -- see https://github.com/apache/apisix/issues/3286
    _M.load()

    if local_conf and not local_conf.apisix.enable_admin then
        init_plugins_syncer()
    end

    local plugin_metadatas, err = core.config.new("/plugin_metadata",
        {
            automatic = true,
            checker = check_plugin_metadata
        }
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
    local http_plugins = {}
    local stream_plugins = {}

    if local_plugins_hash then
        for name, plugin_obj in pairs(local_plugins_hash) do
            http_plugins[name] = core.table.pick(plugin_obj, attrs)
        end
    end

    if stream_local_plugins_hash then
        for name, plugin_obj in pairs(stream_local_plugins_hash) do
            stream_plugins[name] = core.table.pick(plugin_obj, attrs)
        end
    end

    return http_plugins, stream_plugins
end


-- conf_version returns a version which only depends on the value of conf,
-- instead of where this plugin conf belongs to
function _M.conf_version(conf)
    if not conf._version then
        local data = core.json.stably_encode(conf)
        conf._version = tostring(crc32(data))
        core.log.info("init plugin-level conf version: ", conf._version, ", from ", data)
    end

    return conf._version
end


local function check_single_plugin_schema(name, plugin_conf, schema_type, skip_disabled_plugin)
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
            return true
        else
            return false, "unknown plugin [" .. name .. "]"
        end
    end

    if plugin_obj.check_schema then
        local ok, err = plugin_obj.check_schema(plugin_conf, schema_type)
        if not ok then
            return false, "failed to check the configuration of plugin "
                .. name .. " err: " .. err
        end

        if plugin_conf._meta and plugin_conf._meta.filter then
            ok, err = expr.new(plugin_conf._meta.filter)
            if not ok then
                return nil, "failed to validate the 'vars' expression: " .. err
            end
        end
    end

    return true
end


local enable_data_encryption
local function enable_gde()
    if enable_data_encryption == nil then
        enable_data_encryption =
            core.table.try_read_attr(local_conf, "apisix", "data_encryption", "enable")
        _M.enable_data_encryption = enable_data_encryption
    end

    return enable_data_encryption
end


local function get_plugin_schema_for_gde(name, schema_type)
    if not enable_gde() then
        return nil
    end

    local plugin_schema = local_plugins_hash and local_plugins_hash[name]
    if not plugin_schema then
        return nil
    end

    local schema
    if schema_type == core.schema.TYPE_CONSUMER then
        schema = plugin_schema.consumer_schema
    elseif schema_type == core.schema.TYPE_METADATA then
        schema = plugin_schema.metadata_schema
    else
        schema = plugin_schema.schema
    end

    return schema
end


local function decrypt_conf(name, conf, schema_type)
    local schema = get_plugin_schema_for_gde(name, schema_type)
    if not schema then
        core.log.warn("failed to get schema for plugin: ", name)
        return
    end

    if schema.encrypt_fields and not core.table.isempty(schema.encrypt_fields) then
        for _, key in ipairs(schema.encrypt_fields) do
            if conf[key] then
                local decrypted, err = apisix_ssl.aes_decrypt_pkey(conf[key], "data_encrypt")
                if not decrypted then
                    core.log.warn("failed to decrypt the conf of plugin [", name,
                                  "] key [", key, "], err: ", err)
                else
                    conf[key] = decrypted
                end
            elseif core.string.find(key, ".") then
                -- decrypt fields has indents
                local res, err = re_split(key, "\\.", "jo")
                if not res then
                    core.log.warn("failed to split key [", key, "], err: ", err)
                    return
                end

                -- we only support two levels
                if conf[res[1]] and conf[res[1]][res[2]] then
                    local decrypted, err = apisix_ssl.aes_decrypt_pkey(
                                           conf[res[1]][res[2]], "data_encrypt")
                    if not decrypted then
                        core.log.warn("failed to decrypt the conf of plugin [", name,
                                      "] key [", key, "], err: ", err)
                    else
                        conf[res[1]][res[2]] = decrypted
                    end
                end
            end
        end
    end
end
_M.decrypt_conf = decrypt_conf


local function encrypt_conf(name, conf, schema_type)
    local schema = get_plugin_schema_for_gde(name, schema_type)
    if not schema then
        core.log.warn("failed to get schema for plugin: ", name)
        return
    end

    if schema.encrypt_fields and not core.table.isempty(schema.encrypt_fields) then
        for _, key in ipairs(schema.encrypt_fields) do
            if conf[key] then
                local encrypted, err = apisix_ssl.aes_encrypt_pkey(conf[key], "data_encrypt")
                if not encrypted then
                    core.log.warn("failed to encrypt the conf of plugin [", name,
                                  "] key [", key, "], err: ", err)
                else
                    conf[key] = encrypted
                end
            elseif core.string.find(key, ".") then
                -- encrypt fields has indents
                local res, err = re_split(key, "\\.", "jo")
                if not res then
                    core.log.warn("failed to split key [", key, "], err: ", err)
                    return
                end

                -- we only support two levels
                if conf[res[1]] and conf[res[1]][res[2]] then
                    local encrypted, err = apisix_ssl.aes_encrypt_pkey(
                                           conf[res[1]][res[2]], "data_encrypt")
                    if not encrypted then
                        core.log.warn("failed to encrypt the conf of plugin [", name,
                                      "] key [", key, "], err: ", err)
                    else
                        conf[res[1]][res[2]] = encrypted
                    end
                end
            end
        end
    end
end
_M.encrypt_conf = encrypt_conf


check_plugin_metadata = function(item)
    local ok, err = check_single_plugin_schema(item.id, item,
                                               core.schema.TYPE_METADATA, true)
    if ok and enable_gde() then
        decrypt_conf(item.name, item, core.schema.TYPE_METADATA)
    end

    return ok, err
end


local function check_schema(plugins_conf, schema_type, skip_disabled_plugin)
    for name, plugin_conf in pairs(plugins_conf) do
        local ok, err = check_single_plugin_schema(name, plugin_conf,
            schema_type, skip_disabled_plugin)
        if not ok then
            return false, err
        end
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
            local ok, err = plugin_obj.check_schema(plugin_conf, schema_type)
            if not ok then
                return false, "failed to check the configuration of "
                              .. "stream plugin [" .. name .. "]: " .. err
            end
        end

        ::CONTINUE::
    end

    return true
end
_M.stream_check_schema = stream_check_schema


function _M.plugin_checker(item, schema_type)
    if item.plugins then
        local ok, err = check_schema(item.plugins, schema_type, true)

        if ok and enable_gde() then
            -- decrypt conf
            for name, conf in pairs(item.plugins) do
                decrypt_conf(name, conf, schema_type)
            end
        end
        return ok, err
    end

    return true
end


function _M.stream_plugin_checker(item, in_cp)
    if item.plugins then
        return stream_check_schema(item.plugins, nil, not in_cp)
    end

    return true
end


function _M.run_plugin(phase, plugins, api_ctx)
    local plugin_run = false
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
        and phase ~= "delayed_body_filter"
    then
        for i = 1, #plugins, 2 do
            local phase_func
            if phase == "rewrite_in_consumer" then
                if plugins[i].type == "auth" then
                    plugins[i + 1]._skip_rewrite_in_consumer = true
                end
                phase_func = plugins[i]["rewrite"]
            else
                phase_func = plugins[i][phase]
            end

            if phase == "rewrite_in_consumer" and plugins[i + 1]._skip_rewrite_in_consumer then
                goto CONTINUE
            end

            if phase_func then
                local conf = plugins[i + 1]
                if not meta_filter(api_ctx, plugins[i]["name"], conf)then
                    goto CONTINUE
                end

                plugin_run = true
                local code, body = phase_func(conf, api_ctx)
                if code or body then
                    if is_http then
                        if code >= 400 then
                            core.log.warn(plugins[i].name, " exits with http status code ", code)

                            if conf._meta and conf._meta.error_response then
                                -- Whether or not the original error message is output,
                                -- always return the configured message
                                -- so the caller can't guess the real error
                                body = conf._meta.error_response
                            end
                        end

                        core.response.exit(code, body)
                    else
                        if code >= 400 then
                            core.log.warn(plugins[i].name, " exits with status code ", code)
                        end

                        ngx_exit(1)
                    end
                end
            end

            ::CONTINUE::
        end
        return api_ctx, plugin_run
    end

    for i = 1, #plugins, 2 do
        local phase_func = plugins[i][phase]
        local conf = plugins[i + 1]
        if phase_func and meta_filter(api_ctx, plugins[i]["name"], conf) then
            plugin_run = true
            phase_func(conf, api_ctx)
        end
    end

    return api_ctx, plugin_run
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
        local route = api_ctx.matched_route
        for _, global_rule in config_util.iterate_values(values) do
            api_ctx.conf_type = "global_rule"
            api_ctx.conf_version = global_rule.modifiedIndex
            api_ctx.conf_id = global_rule.value.id

            core.table.clear(plugins)
            plugins = _M.filter(api_ctx, global_rule, plugins, route)
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
