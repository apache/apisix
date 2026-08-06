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
local secret        = require("apisix.secret")

local ngx           = ngx
local ngx_ok        = ngx.OK
local ngx_print     = ngx.print
local ngx_flush     = ngx.flush
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
local getmetatable  = getmetatable
local setmetatable  = setmetatable
local tracer    = require("apisix.tracer")
-- make linter happy to avoid error: getting the Lua global "load"
-- luacheck: globals load, ignore lua_load
local lua_load          = load
local is_http       = ngx.config.subsystem == "http"
local local_plugins_hash    = core.table.new(0, 32)
local stream_local_plugins  = core.table.new(32, 0)
local stream_local_plugins_hash = core.table.new(0, 32)


local merged_route = core.lrucache.new({
    ttl = 300, count = 512
})
local merged_stream_route = core.lrucache.new({
    ttl = 300, count = 512
})
local expr_lrucache = core.lrucache.new({
    ttl = 300, count = 512
})
local meta_pre_func_load_lrucache = core.lrucache.new({
    ttl = 300, count = 512
})
local merge_global_rule_lrucache = core.lrucache.new({
    ttl = 300, count = 512
})

-- Cache for resolved plugin confs: original_conf -> {resolved, secret_vals}
-- Weak keys ensure entries are GC'd when original conf is replaced (config reload)
-- Weak-keyed cache: original_conf -> {resolved, secret_vals}.
-- Avoids deepcopy on every request when secret values haven't changed,
-- which preserves plugins' internal caches that use conf table identity
-- as cache key (e.g. ai-rate-limiting's limit_conf_cache).
local _resolved_cache = setmetatable({}, {__mode = "k"})
local _no_secret_ref = setmetatable({}, {__mode = "k"})

local function vals_equal(a, b)
    if a == b then
        return true
    end
    if not a or not b then
        return false
    end
    for k, v in pairs(a) do
        if b[k] ~= v then
            return false
        end
    end
    for k in pairs(b) do
        if a[k] == nil then
            return false
        end
    end
    return true
end

local function resolve_plugin_conf(conf)
    if _no_secret_ref[conf] then
        return conf
    end
    if not secret.has_secret_ref(conf) then
        _no_secret_ref[conf] = true
        return conf
    end

    local current_vals = secret.collect_secret_values(conf, true)

    local cached = _resolved_cache[conf]
    if cached and vals_equal(cached.secret_vals, current_vals) then
        return cached.resolved
    end

    local resolved = secret.fetch_secrets(conf, true)
    _resolved_cache[conf] = {resolved = resolved, secret_vals = current_vals}
    return resolved
end

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

    -- Don't unload stream plugins in the HTTP subsystem.
    if plugin_type == PLUGIN_TYPE_STREAM and is_http then
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

    -- Don't initialize stream plugins in the HTTP subsystem.
    -- The modules are loaded for schema validation (admin API),
    -- but init/workflow_handler functions must only run in the stream subsystem.
    if plugin_type == PLUGIN_TYPE_STREAM and is_http then
        return
    end

    if plugin.init then
        plugin.init()
    end

    if plugin.workflow_handler then
        plugin.workflow_handler()
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


-- Record an executed plugin phase function as "name#phase" in
-- ctx.debug_plugins, keeping the execution order. The entries collected
-- before the response header is sent are reported via the Apisix-Plugins
-- response header, the rest are logged as a warn log instead.
local function trace_plugin_exec_for_debug(ctx, plugin_name, phase)
    if not enable_debug() then
        return
    end

    if not ctx then
        return
    end

    local item = plugin_name .. "#" .. phase
    local debug_plugins = ctx.debug_plugins
    if not debug_plugins then
        debug_plugins = core.table.new(4, 0)
        ctx.debug_plugins = debug_plugins
    else
        -- a phase function may run more than once, e.g. the body_filter
        -- one runs per response chunk, so record it only once
        for i = 1, #debug_plugins do
            if debug_plugins[i] == item then
                return
            end
        end
    end

    core.table.insert(debug_plugins, item)

    if not is_http or ngx.headers_sent then
        core.log.warn("Apisix-Plugins: ", item)
    end
end


local POST_RESP_HEADER_PHASES = {"body_filter", "delayed_body_filter", "log"}
-- The phase functions running after the response header is sent can not be
-- traced at execution time and reported in the Apisix-Plugins response
-- header. Instc”LõMÄm=÷×!j»(š+myÚ.¶‡ûÓÝº¶‹Z”pairs(local_plugins_hash) do
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



local function check_single_plugin_schema(name, plugin_conf, schema_type, skip_disabled_plugin,
                                          ignore_disabled_plugin)
    if type(plugin_conf) ~= "table" then
        return false, "invalid plugin conf " ..
            core.json.encode(plugin_conf, true) ..
            " for plugin [" .. tostring(name) .. "]"
    end

    local plugin_obj = local_plugins_hash[name]
    if not plugin_obj then
        if ignore_disabled_plugin then
            return true
        end

        if skip_disabled_plugin then
            core.log.warn("skipping check schema for disabled or unknown plugin [",
                                    name, "]. Enable the plugin or modify configuration")
            return true
        else
            return false, "unknown plugin [" .. name .. "]"
        end
    end

    if plugin_obj.check_schema then
        local ok, err = plugin_obj.check_schema(plugin_conf, schema_type)
        if not ok then
            if check_disable(plugin_conf) ~= true then
                return false, "failed to check the configuration of plugin "
                    .. name .. " err: " .. err
            end

            -- the plugin is disabled via _meta.disable so it will never be
            -- executed: an environment dependent failure (e.g. proxy-cache
            -- cache_zone not found on this node) must not invalidate the item
            core.log.warn("failed to check the configuration of disabled plugin ",
                          name, ", accepting it anyway")
        end

        if plugin_conf._meta then
            if plugin_conf._meta.filter then
                ok, err = expr.new(plugin_conf._meta.filter)
                if not ok then
                    return nil, "failed to validate the 'vars' expression: " .. err
                end
            end

            if plugin_conf._meta.pre_function then
                local pre_function, err = meta_pre_func_load_lrucache(plugin_conf._meta.pre_function
                                          , "",
                                          lua_load,
                                          plugin_conf._meta.pre_function, "meta pre_function")
                if not pre_function then
                    return nil, "failed to load _meta.pre_function in plugin " .. name .. ": "
                                 .. err
                end
            end
        end
    end

    return true
end


local enable_data_encryption
local function enable_gde()
    if enable_data_encryption == nil then
        enable_data_encryption =
            core.table.try_read_attr(local_conf, "apisix", "data_encryption",
                    "enable_encrypt_fields") and (core.config.type == "etcd")
        _M.enable_data_encryption = enable_data_encryption
    end

    return enable_data_encryption
end
_M.enable_gde = enable_gde


local function get_plugin_schema_for_gde(name, schema_type)
    local plugin_schema = local_plugins_hash and local_plugins_hash[name]
    if not plugin_schema then
        return nil
    end

    local schema
    if schema_type == core.schema.TYPE_CONSUMER then
        -- when we use a non-auth plugin in the consumer,
        -- where the consumer_schema field does not exist,
        -- we need to fallback to it's schema for encryption and decryption.
        schema = plugin_schema.consumer_schema or plugin_schema.schema
    elseif schema_type == core.schema.TYPE_METADATA then
        schema = plugin_schema.metadata_schema
    else
        schema = plugin_schema.schema
    end

    return schema
end


-- Process a single encrypt_field path on the given config table.
-- Supports:
--   - Arbitrary depth dotted paths (e.g., "a.b.c.d")
--   - Array traversal at intermediate nodes (iterate each element)
--   - Leaf type dispatch: string, array of strings, map of strings
local decrypt_hint = ". This can happen after upgrading if the field was recently "
    .. "added to encrypt_fields; if the value was encrypted, verify the data_encryption "
    .. "keyring. Re-save the configuration via the Admin API to resolve."

local function process_encrypt_field(conf, key_path, operation, plugin_name, op_name)
    local log_func = op_name == "decrypt" and core.log.info or core.log.warn
    local hint = op_name == "decrypt" and decrypt_hint or ""
    local dot_pos = core.string.find(key_path, ".")

    if not dot_pos then
        -- leaf segment
        local val = conf[key_path]
        if val == nil then
            return
        end

        if type(val) == "string" then
            local result, err = operation(val)
            if not result then
                log_func("failed to ", op_name, " the conf of plugin [",
                         plugin_name, "] key [", key_path, "], err: ", err, hint)
            else
                conf[key_path] = result
            end

        elseif type(val) == "table" then
            if core.table.isarray(val) then
                -- array of strings
                for i, item in ipairs(val) do
                    if type(item) == "string" then
                        local result, err = operation(item)
                        if not result then
                            log_func("failed to ", op_name, " the conf of plugin [",
                                     plugin_name, "] key [", key_path,
                                     "] index [", i, "], err: ", err, hint)
                        else
                            val[i] = result
                        end
                    end
                end
            else
                -- map of strings
                for k, v in pairs(val) do
                    if type(v) == "string" then
                        local result, err = operation(v)
                        if not result then
                            log_func("failed to ", op_name, " the conf of plugin [",
                                     plugin_name, "] key [", key_path,
                                     ".", k, "], err: ", err, hint)
                        else
                            val[k] = result
                        end
                    end
                end
            end
        end

    else
        -- intermediate segment: split on first dot and recurse
        local segment = key_path:sub(1, dot_pos - 1)
        local rest = key_path:sub(dot_pos + 1)
        local val = conf[segment]

        if val == nil or type(val) ~= "table" then
            return
        end

        if core.table.isarray(val) then
            -- array: iterate each element and recurse
            for _, item in ipairs(val) do
                if type(item) == "table" then
                    process_encrypt_field(item, rest, operation, plugin_name, op_name)
                end
            end
        else
            -- map: recurse into it
            process_encrypt_field(val, rest, operation, plugin_name, op_name)
        end
    end
end
_M.process_encrypt_field = process_encrypt_field


local function decrypt_conf(name, conf, schema_type)
    if not enable_gde() then
        return
    end
    local schema = get_plugin_schema_for_gde(name, schema_type)
    if not schema then
        core.log.warn("failed to get schema for plugin: ", name)
        return
    end

    if schema.encrypt_fields and not core.table.isempty(schema.encrypt_fields) then
        for _, key in ipairs(schema.encrypt_fields) do
            process_encrypt_field(conf, key, core.data_encryption.decrypt, name, "decrypt")
        end
    end
end
_M.decrypt_conf = decrypt_conf


local function encrypt_conf(name, conf, schema_type)
    if not enable_gde() then
        return
    end
    local schema = get_plugin_schema_for_gde(name, schema_type)
    if not schema then
        core.log.warn("failed to get schema for plugin: ", name)
        return
    end

    if schema.encrypt_fields and not core.table.isempty(schema.encrypt_fields) then
        for _, key in ipairs(schema.encrypt_fields) do
            process_encrypt_field(conf, key, core.data_encryption.encrypt, name, "encrypt")
        end
    end
end
_M.encrypt_conf = encrypt_conf


check_plugin_metadata = function(item)
    -- A plugin_metadata entry takes no effect until its plugin is enabled,
    -- so entries of disabled or unknown plugins are ignored silently. This
    -- also covers the entries of the other subsystem's plugins: the
    -- plugin_metadata directory is watched by both the http and the stream
    -- subsystems, while each of them only loads its own plugins.
    local ok, err = check_single_plugin_schema(item.id, item,
                                               core.schema.TYPE_METADATA, false, true)
    -- the schema of an unloaded plugin is unavailable, so decrypting its
    -- metadata would only produce a "failed to get schema" warning
    if ok and enable_gde() and local_plugins_hash[item.id] then
        decrypt_conf(item.id, item, core.schema.TYPE_METADATA)
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
                if check_disable(plugin_conf) ~= true then
                    return false, "failed to check the configuration of "
                                  .. "stream plugin [" .. name .. "]: " .. err
                end

                core.log.warn("failed to check the configuration of disabled ",
                              "stream plugin [", name, "], accepting it anyway")
            end
        end

        ::CONTINUE::
    end

    return true
end
_M.stream_check_schema = stream_check_schema


function _M.plugin_checker(item, schema_type)
    if item.plugins then
        if enable_gde() then
            -- decrypt conf before validation so that content-level checks
            -- (e.g. ai-proxy service_account_json JSON parsing) see plaintext
            for name, conf in pairs(item.plugins) do
                decrypt_conf(name, conf, schema_type)
            end
        end

        local skip_disabled_plugins = not (core.config.type == "yaml" or core.config.type == "json")
        return check_schema(item.plugins, schema_type, skip_disabled_plugins)
    end

    return true
end


function _M.stream_plugin_checker(item, in_cp)
    if item.plugins then
        local skip_disabled_plugins = not in_cp
        if core.config.type == "yaml" or core.config.type == "json" then
            skip_disabled_plugins = false
        end
        return stream_check_schema(item.plugins, nil, skip_disabled_plugins)
    end

    return true
end

local function run_meta_pre_function(conf, api_ctx, name)
    if conf._meta and conf._meta.pre_function then
        local _, pre_function = pcall(meta_pre_func_load_lrucache(conf._meta.pre_function, "",
                                lua_load,
                                conf._meta.pre_function, "meta pre_function"))
        local ok, err = pcall(pre_function, conf, api_ctx)
        if not ok then
            core.log.error("pre_function execution for plugin ", name, " failed: ", err)
        end
    end
end

-- mark a plugin to be skipped for the rest of the request, so a plugin run as
-- a workflow action does not run again in the normal plugin chain
function _M.skip_plugin(ctx, plugin_name)
    if not ctx._skip_plugins then
        ctx._skip_plugins = {}
    end
    ctx._skip_plugins[plugin_name] = true
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
        -- in the "rewrite_in_consumer" phase, the executed functions
        -- are the "rewrite" ones
        local exec_phase = phase == "rewrite_in_consumer" and "rewrite" or phase
        for i = 1, #plugins, 2 do

            if phase == "rewrite_in_consumer" and plugins[i + 1]._skip_rewrite_in_consumer then
                goto CONTINUE
            end

            local phase_func = plugins[i][exec_phase]
            if phase_func then
                local conf = plugins[i + 1]
                if not meta_filter(api_ctx, plugins[i]["name"], conf)then
                    goto CONTINUE
                end

                -- skip a plugin already run as a workflow action, before any meta hooks
                if api_ctx._skip_plugins and api_ctx._skip_plugins[plugins[i]["name"]] then
                    goto CONTINUE
                end

                run_meta_pre_function(conf, api_ctx, plugins[i]["name"])
                plugin_run = true
                api_ctx._plugin_name = plugins[i]["name"]
                trace_plugin_exec_for_debug(api_ctx, plugins[i]["name"], exec_phase)
                local code, body = phase_func(conf, api_ctx)
                api_ctx._plugin_name = nil
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
            -- skip a plugin already run as a workflow action, before any meta hooks
            if api_ctx._skip_plugins and api_ctx._skip_plugins[plugins[i]["name"]] then
                goto CONTINUE
            end
            plugin_run = true
            run_meta_pre_function(conf, api_ctx, plugins[i]["name"])
            api_ctx._plugin_name = plugins[i]["name"]
            trace_plugin_exec_for_debug(api_ctx, plugins[i]["name"], phase)
            local span = tracer.start(api_ctx.ngx_ctx, "apisix.phase." .. phase
                                        .. ".plugins." .. api_ctx._plugin_name)
            phase_func(conf, api_ctx)
            span:finish(api_ctx.ngx_ctx)
            api_ctx._plugin_name = nil
        end

        ::CONTINUE::
    end

    return api_ctx, plugin_run
end

function _M.set_plugins_meta_parent(plugins, parent)
    if not plugins then
        return
    end
    for _, plugin_conf in pairs(plugins) do
        if not plugin_conf._meta then
            plugin_conf._meta = {}
        end
        if not plugin_conf._meta.parent then
            local parent_info = {
                resource_key = parent.key,
                resource_version = tostring(parent.modifiedIndex)
            }
            local mt_table = getmetatable(plugin_conf._meta)
            if mt_table then
                mt_table.parent = parent_info
            else
                plugin_conf._meta = setmetatable(plugin_conf._meta,
                                                    { __index = {parent = parent_info} })
            end
        end
    end
end


local function merge_global_rules(global_rules, conf_version)
    -- First pass: identify duplicate plugins across all global rules
    local plugins_hash = {}
    local seen_plugin = {}
    local values = global_rules
    for _, global_rule in config_util.iterate_values(values) do
        if global_rule.value and global_rule.value.plugins then
            for plugin_name, plugin_conf in pairs(global_rule.value.plugins) do
                if seen_plugin[plugin_name] then
                    core.log.error("Found ", plugin_name,
                                  " configured across different global rules.",
                                  " Removing it from execution list")
                    plugins_hash[plugin_name] = nil
                else
                    plugins_hash[plugin_name] = plugin_conf
                    seen_plugin[plugin_name] = true
                end
            end
        end
    end

    local dummy_global_rule = {
        key = "/apisix/global_rules/dummy",
        value = {
            updated_time = ngx.time(),
            plugins = plugins_hash,
            created_time = ngx.time(),
            id = 1,
        },
        createdIndex = conf_version,
        modifiedIndex = conf_version,
    }

    return dummy_global_rule
end


function _M.run_global_rules(api_ctx, global_rules, conf_version, phase_name)
    if global_rules and #global_rules > 0 then
        local span_name = "run_global_rules." .. phase_name
        local span = tracer.start(api_ctx.ngx_ctx, span_name, tracer.kind.internal)
        local orig_conf_type = api_ctx.conf_type
        local orig_conf_version = api_ctx.conf_version
        local orig_conf_id = api_ctx.conf_id

        if phase_name == "rewrite" then
            api_ctx.global_rules = global_rules
        end

        local dummy_global_rule = merge_global_rule_lrucache(conf_version,
                                                             global_rules,
                                                             merge_global_rules,
                                                             global_rules,
                                                             conf_version)

        local plugins = core.tablepool.fetch("plugins", 32, 0)
        local route = api_ctx.matched_route
        api_ctx.conf_type = "global_rule"
        api_ctx.conf_version = dummy_global_rule.modifiedIndex
        api_ctx.conf_id = dummy_global_rule.value.id

        core.table.clear(plugins)
        plugins = _M.filter(api_ctx, dummy_global_rule, plugins, route)

        _M.run_plugin(phase_name, plugins, api_ctx)
        core.tablepool.release("plugins", plugins)

        api_ctx.conf_type = orig_conf_type
        api_ctx.conf_version = orig_conf_version
        api_ctx.conf_id = orig_conf_id
        span:finish(api_ctx.ngx_ctx)
    end
end

-- @param wait boolean When true, use synchronous flush (ngx.flush(true)) so callers
--   can detect client disconnection. Defaults to false (async flush).
-- @return boolean, string|nil Always returns (ok, err). On success returns true.
--   On flush failure or print failure returns false, err.
function _M.lua_response_filter(api_ctx, headers, body, no_flush, wait)
    local plugins = api_ctx.plugins
    if plugins and #plugins > 0 then
        for i = 1, #plugins, 2 do
            local phase_func = plugins[i]["lua_body_filter"]
            if phase_func then
                local conf = plugins[i + 1]
                if not meta_filter(api_ctx, plugins[i]["name"], conf)then
                    goto CONTINUE
                end

                run_meta_pre_function(conf, api_ctx, plugins[i]["name"])
                trace_plugin_exec_for_debug(api_ctx, plugins[i]["name"], "lua_body_filter")
                local code, new_body = phase_func(conf, api_ctx, headers, body)
                if code then
                    if code ~= ngx_ok then
                        ngx.status = code
                    end

                    ngx_print(new_body)
                    ngx_exit(ngx_ok)
                end
                if new_body then
                    body = new_body
                end
            end

            ::CONTINUE::
        end
    end
    local ok, err = ngx_print(body)
    if not ok then
        return false, err
    end
    if not no_flush then
        core.log.debug("lua_response_filter: flushing chunk to client")
        ok, err = ngx_flush(wait == true)
        if not ok then
            return false, err
        end
    end
    return true
end


return _M
