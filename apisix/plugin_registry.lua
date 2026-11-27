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
local lfs = require("lfs")
local source_dir = debug.getinfo(1, "S").source:match("^@(.*)/plugin_registry.lua$")
local statuses = {}

local _M = {
    active_path = "/plugin_registry_active",
    draft_path = "/plugin_registry_drafts",
    version_path = "/plugin_registry_versions",
    max_source = 256 * 1024,
    bundled = "bundled",
}


function _M.enabled()
    local conf = core.config.local_conf()
    local opts = conf and conf.plugin_attr and conf.plugin_attr.plugin_registry
    return type(opts) == "table" and opts.enabled == true
        and conf.deployment.config_provider == "etcd"
end


local function valid_component(value, limit)
    return type(value) == "string" and #value <= limit
        and value:match("^[a-zA-Z0-9][a-zA-Z0-9_.-]*$") ~= nil
end


function _M.split(id)
    if type(id) ~= "string" then
        return nil
    end
    local subsystem, name = id:match("^(%a+)~(.+)$")
    if (subsystem == "http" or subsystem == "stream") and valid_component(name, 64)
       and not name:find(".", 1, true) then
        return subsystem, name
    end
end


function _M.valid_version(version)
    return valid_component(version, 48) and version ~= _M.bundled
end


local function builtin_dir(subsystem)
    return source_dir .. (subsystem == "stream" and "/stream/plugins" or "/plugins")
end


function _M.builtin_source(id)
    local subsystem, name = _M.split(id)
    if not subsystem then
        return nil
    end
    local file = io.open(builtin_dir(subsystem) .. "/" .. name .. ".lua", "rb")
    if not file then
        return nil
    end
    local source = file:read(_M.max_source + 1)
    file:close()
    if source and #source <= _M.max_source then
        return source
    end
end


function _M.builtins()
    local plugins = {}
    for _, subsystem in ipairs({"http", "stream"}) do
        local dir = builtin_dir(subsystem)
        if lfs.attributes(dir, "mode") == "directory" then
            for file in lfs.dir(dir) do
                local name = file:match("^(.+)%.lua$")
                local id = name and subsystem .. "~" .. name
                if id and _M.split(id) and lfs.attributes(dir .. "/" .. file, "mode") == "file" then
                    plugins[id] = true
                end
            end
        end
    end
    return plugins
end


function _M.compile(id, source)
    local subsystem, name = _M.split(id)
    if not subsystem or type(source) ~= "string" or #source == 0 or #source > _M.max_source
       or source:byte(1) == 27 then
        return nil, "expected a nonempty Lua source file of at most 256 KiB"
    end
    -- loadstring is used under LuaJIT. The leading byte check rejects bytecode there.
    -- luacheck: globals load loadstring
    local loader, err = (loadstring or load)(source, "@plugin_registry/" .. id)
    if not loader then
        return nil, err
    end
    local module = subsystem == "stream" and "apisix.stream.plugins." or "apisix.plugins."
    local ok, plugin = pcall(loader, module .. name)
    if not ok then
        return nil, tostring(plugin)
    end
    if type(plugin) ~= "table" or type(plugin.schema) ~= "table"
        or type(plugin.priority) ~= "number" or plugin.priority ~= plugin.priority
        or math.abs(plugin.priority) == math.huge or type(plugin.version) ~= "number"
        or (plugin.schema.properties and type(plugin.schema.properties) ~= "table")
    then
        return nil, "plugin must return a module with a numeric priority and version and a schema"
    end
    if plugin.schema.properties and plugin.schema.properties._meta
        and plugin.schema['$comment'] ~= core.schema.plugin_injected_schema['$comment']
    then
        return nil, "the plugin schema cannot declare _meta"
    end
    for _, hook in ipairs({"init", "destroy", "workflow_handler", "check_schema"}) do
        if plugin[hook] ~= nil and type(plugin[hook]) ~= "function" then
            return nil, hook .. " must be a function"
        end
    end
    return plugin
end


local function equal(old, new, seen, schema, properties)
    if old == new then
        return true
    end
    -- The loader creates a properties table even when the source only uses _meta.
    if properties then
        if old == nil then
            old = {}
        end
        if new == nil then
            new = {}
        end
    end
    if type(old) ~= "table" or type(new) ~= "table" then
        return false
    end
    if seen[old] == new then
        return true
    end
    seen[old] = new
    for key, value in pairs(old) do
        if not ((schema and key == "$comment") or (properties and key == "_meta"))
            and not equal(value, new[key], seen, false, schema and key == "properties") then
            return false
        end
    end
    for key, value in pairs(new) do
        if old[key] == nil and not ((schema and key == "$comment")
            or (properties and key == "_meta"))
            and not equal(nil, value, seen, false, schema and key == "properties") then
            return false
        end
    end
    return true
end


function _M.compatible(old, new)
    for _, field in ipairs({"schema", "consumer_schema", "metadata_schema", "encrypt_fields",
                             "type", "scope", "run_policy"}) do
        if not equal(old[field], new[field], {}, field == "schema", false) then
            return nil, "plugin compatibility check failed for " .. field
        end
    end
    return true
end


-- Retire shared timers and event handlers before initializing their replacements.
local function run_hook(hook)
    if hook then
        return pcall(hook)
    end
    return true
end


function _M.activate(release, name, plugins, hash, kind, load, order, plugin_module)
    local subsystem = _M.split(release.id)
    local stream = subsystem == "stream"
    local lifecycle = not stream or ngx.config.subsystem == "stream"
    local old = hash[name]
    if old and old.type == "wasm" then
        return nil, "plugin name is already in use by a Wasm plugin"
    end

    local source = release.source
    if release.version == _M.bundled then
        source = _M.builtin_source(release.id)
    end
    local candidate, err = _M.compile(release.id, source)
    if not candidate then
        return nil, err
    end
    if old then
        local compatible, compatibility_err = _M.compatible(old, candidate)
        if not compatible then
            return nil, compatibility_err
        end
    end

    if lifecycle and old then
        local retired, retire_err = run_hook(old.destroy)
        if not retired then
            return nil, retire_err
        end
    end

    local staged = {}
    local ok, init_err = pcall(load, name, staged, kind, candidate)
    if not ok or not staged[1] then
        if lifecycle and staged[1] then
            run_hook(candidate.destroy)
        end
        if lifecycle and old then
            local restored, restore_err = run_hook(old.init)
            if restored then
                restored, restore_err = run_hook(old.workflow_handler)
            end
            if not restored then
                core.log.error("failed to reinitialize plugin ", name, ": ", restore_err)
            end
        end
        return nil, ok and "plugin validation failed" or init_err
    end

    hash[name] = candidate
    local index = #plugins + 1
    for i, loaded in ipairs(plugins) do
        if loaded.name == name then
            index = i
            break
        end
    end
    plugins[index] = candidate
    table.sort(plugins, order)
    local prefix = stream and "apisix.stream.plugins." or "apisix.plugins."
    package.loaded[prefix .. name] = candidate
    local counter = stream and "stream_load_times" or "load_times"
    plugin_module[counter] = plugin_module[counter] + 1
    return true
end


function _M.status(id)
    return statuses[id]
end


function _M.reconciler(swap)
    return function(release)
        local id = release.id
        local status = statuses[id] or {}
        if status.desired == release.version then
            return
        end
        status.desired = release.version
        local ran, ok, err = pcall(swap, release)
        if ran and ok then
            status.effective = release.version
            status.error = nil
        else
            status.error = tostring(ran and err or ok)
            core.log.error("failed to activate registry plugin ", id, ": ", status.error)
        end
        statuses[id] = status
    end
end


local watcher
local reconcile


function _M.init_worker(swap)
    if not _M.enabled() then
        return
    end
    reconcile = _M.reconciler(swap)
    local err
    watcher, err = core.config.new(_M.active_path, {
        automatic = true,
        item_schema = {
            type = "object",
            properties = {
                version = {type = "string", maxLength = 48},
                source = {type = "string", maxLength = _M.max_source},
            },
            required = {"version"},
        },
        filter = function(item)
            reconcile(item.value)
        end,
    })
    if not watcher then
        core.log.error("failed to watch plugin registry: ", err)
    end
end


function _M.reapply()
    if not watcher then
        return
    end
    for _, item in ipairs(watcher.values) do
        if item and item.value then
            statuses[item.value.id] = nil
            reconcile(item.value)
        end
    end
end


return _M
