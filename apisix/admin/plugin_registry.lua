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
local bit = require("bit")
local core = require("apisix.core")
local registry = require("apisix.plugin_registry")
local path_active = registry.active_path
local path_draft = registry.draft_path
local path_version = registry.version_path

local _M = {}


local function failure(status, message)
    return status, {error_msg = message}
end


local function read(path, directory)
    local res, err = core.etcd.get(path, directory)
    if not res then
        return nil, err or "failed to read plugin registry"
    end
    if res.status == 404 then
        return {}
    end
    if res.status ~= 200 then
        return nil, "failed to read plugin registry: " .. res.status
    end
    if directory then
        return {nodes = res.body.list or res.body.node and res.body.node.nodes}
    end
    return res.body.node
end


local function revision(node)
    return tostring(node.modifiedIndex or 0)
end


local function write(path, value, current)
    local res, err = core.etcd.atomic_set(path, value, nil, revision(current))
    if not res then
        if err == "value changed before overwritten" then
            return failure(409, "plugin registry changed, reload before retrying")
        end
        return failure(503, err or "failed to update plugin registry")
    end
    return 200, {revision = revision({modifiedIndex = res.headers["X-Etcd-Index"]})}
end


local function publish_version(draft_key, draft, key, existing, note, active_key, current, version)
    local cli, prefix, err = core.etcd.get_etcd_cli()
    if not cli then
        return failure(503, err or "failed to connect to etcd")
    end
    draft_key = prefix .. draft_key
    key = prefix .. key
    active_key = prefix .. active_key
    local compare = {
        {key = draft_key, target = "MOD", result = "EQUAL", mod_revision = revision(draft)},
        {key = key, target = "MOD", result = "EQUAL", mod_revision = revision(existing)},
        {key = active_key, target = "MOD", result = "EQUAL", mod_revision = revision(current)},
    }
    local updates = {{requestPut = {key = active_key, value = version}}}
    if not existing.value then
        updates[#updates + 1] = {requestPut = {key = key, value = {
            version = version.version,
            source = version.source,
            note = note,
            created_at = ngx.time(),
        }}}
    end
    local res, txn_err = cli:txn(compare, updates)
    if not res or res.status ~= 200 then
        return failure(503, txn_err or "failed to publish plugin version")
    end
    if not res.body.succeeded then
        return failure(409, "plugin registry changed, reload before retrying")
    end
    return 200, {revision = tostring(res.body.header.revision)}
end


local function loaded_plugin(subsystem, name)
    local plugin = require("apisix.plugin")
    if subsystem == "stream" then
        return plugin.get_stream(name)
    end
    return plugin.get(name)
end


function _M.include_loaded_plugins(subsystem, priorities, names)
    if not registry.enabled() then
        return
    end
    local http_plugins, stream_plugins = require("apisix.plugin").get_all({priority = true})
    local plugins = subsystem == "stream" and stream_plugins or http_plugins
    for name, plugin in pairs(plugins) do
        local status = registry.status(subsystem .. "~" .. name)
        if not priorities[name] and status and status.effective then
            priorities[name] = plugin.priority
            names[#names + 1] = name
        end
    end
end


local function describe(id, builtin, active)
    local subsystem, name = registry.split(id)
    local status = registry.status(id) or {}
    local effective = status.effective
    if not effective and builtin then
        if loaded_plugin(subsystem, name) then
            effective = registry.bundled
        end
    end
    return {
        id = id,
        name = name,
        subsystem = subsystem,
        builtin = builtin == true,
        desired = active and active.version or nil,
        effective = effective,
        error = status.error,
    }
end


local function catalogue()
    local active, active_err = read(path_active, true)
    local drafts, draft_err = read(path_draft, true)
    if not active or not drafts then
        return failure(503, active_err or draft_err)
    end
    local builtins = registry.builtins()
    local releases = {}
    local ids = {}
    for id in pairs(builtins) do
        ids[id] = true
    end
    for _, node in ipairs(active.nodes or {}) do
        local id = node.key:match("/([^/]+)$")
        if registry.split(id) then
            ids[id] = true
            releases[id] = node.value
        end
    end
    for _, node in ipairs(drafts.nodes or {}) do
        local id = node.key:match("/([^/]+)$")
        if registry.split(id) then
            ids[id] = true
        end
    end
    local plugins = core.table.new(0, 0)
    for id in pairs(ids) do
        plugins[#plugins + 1] = describe(id, builtins[id], releases[id])
    end
    table.sort(plugins, function(a, b) return a.id < b.id end)
    return 200, {enabled = true, plugins = plugins}
end


function _M:get(id, _, sub_path, args)
    if not registry.enabled() then
        return 200, {enabled = false}
    end
    if sub_path and sub_path ~= "" then
        return failure(404, "plugin registry endpoint not found")
    end
    if not id then
        return catalogue()
    end
    if not registry.split(id) then
        return failure(400, "invalid plugin identifier")
    end
    if args and args.version ~= nil then
        if not registry.valid_version(args.version) then
            return failure(400, "invalid plugin version")
        end
        local node, err = read(path_version .. "/" .. id .. "/" .. args.version)
        if not node then
            return failure(503, err)
        end
        if not node.value then
            return failure(404, "plugin version not found")
        end
        return 200, node.value
    end
    local draft, draft_err = read(path_draft .. "/" .. id)
    local active, active_err = read(path_active .. "/" .. id)
    local versions, versions_err = read(path_version .. "/" .. id, true)
    if not draft or not active or not versions then
        return failure(503, draft_err or active_err or versions_err)
    end
    local base = registry.builtin_source(id)
    if not base and not draft.value and not active.value and not versions.nodes then
        return failure(404, "plugin not found")
    end
    local detail = describe(id, base ~= nil, active.value)
    detail.bundled_source = base
    detail.draft = draft.value
    detail.draft_revision = revision(draft)
    detail.active_revision = revision(active)
    detail.versions = {}
    for _, node in ipairs(versions.nodes or {}) do
        local value = node.value
        detail.versions[#detail.versions + 1] = {
            version = value.version, note = value.note, created_at = value.created_at,
        }
    end
    table.sort(detail.versions, function(a, b)
        if a.created_at == b.created_at then
            return a.version > b.version
        end
        return a.created_at > b.created_at
    end)
    return 200, detail
end


local function can_write()
    if not registry.enabled() then
        return nil, "plugin registry is disabled"
    end
    local conf = core.config.local_conf()
    local admin = conf.deployment.admin
    if not admin or admin.admin_key_required == false or not admin.admin_key then
        return nil, "plugin registry requires Admin API authentication"
    end
    local key = conf.plugin_attr.plugin_registry.release_key
    local provided = core.request.header(nil, "X-Plugin-Release-Key")
    if type(key) ~= "string" or #key < 32 or type(provided) ~= "string"
        or #key ~= #provided then
        return nil, "plugin release key is missing or invalid"
    end
    local difference = 0
    for i = 1, #key do
        difference = bit.bor(difference, bit.bxor(key:byte(i), provided:byte(i)))
    end
    if difference ~= 0 then
        return nil, "plugin release key is missing or invalid"
    end
    return true
end


function _M:put(id, body, sub_path)
    local ok, err = can_write()
    if not ok then
        return failure(403, err)
    end
    if (sub_path and sub_path ~= "") or not registry.split(id) or type(body) ~= "table"
        or type(body.source) ~= "string" or #body.source == 0
        or #body.source > registry.max_source or type(body.draft_revision) ~= "string" then
        return failure(400, "expected a plugin identifier, Lua source and draft revision")
    end
    local path = path_draft .. "/" .. id
    local current, read_err = read(path)
    if not current then
        return failure(503, read_err)
    end
    if body.draft_revision ~= revision(current) then
        return failure(409, "plugin draft changed, reload before retrying")
    end
    return write(path, {source = body.source}, current)
end


local function validate(id, candidate_source, active)
    local candidate, compile_err = registry.compile(id, candidate_source)
    if not candidate then
        return failure(400, compile_err)
    end
    local subsystem, name = registry.split(id)
    local loaded = loaded_plugin(subsystem, name)
    if loaded and loaded.type == "wasm" then
        return failure(409, "plugin name is already in use by a Wasm plugin")
    end
    local previous = active and active.source
    if not previous and not loaded and registry.ready() and registry.file_plugins_enabled() then
        previous = registry.builtin_source(id)
    end
    local baseline = loaded
    if previous then
        local err
        baseline, err = registry.compile(id, previous)
        if not baseline then
            return failure(409, "cannot validate the current plugin contract: " .. err)
        end
    end
    if baseline then
        local ok, err = registry.compatible(baseline, candidate)
        if not ok then
            return failure(409, err)
        end
    end
    return 200
end


function _M:post(id, body, sub_path)
    local ok, err = can_write()
    if not ok then
        return failure(403, err)
    end
    if (sub_path and sub_path ~= "") or not registry.split(id) or type(body) ~= "table"
        or type(body.active_revision) ~= "string"
        or (body.action ~= "publish" and body.action ~= "activate")
        or (not registry.valid_version(body.version)
            and not (body.action == "activate" and body.version == registry.bundled)) then
        return failure(400, "expected a valid action, plugin version and active revision")
    end
    local active_key = path_active .. "/" .. id
    local current, read_err = read(active_key)
    if not current then
        return failure(503, read_err)
    end
    if body.active_revision ~= revision(current) then
        return failure(409, "active version changed, reload before retrying")
    end
    local key = path_version .. "/" .. id .. "/" .. body.version
    local version = {version = body.version}
    local source, draft
    local draft_key = path_draft .. "/" .. id
    if body.action == "publish" then
        local draft_err
        draft, draft_err = read(draft_key)
        if not draft then
            return failure(503, draft_err)
        end
        if not draft.value or body.draft_revision ~= revision(draft) then
            return failure(409, "save or reload the draft before publishing")
        end
        if body.note ~= nil and (type(body.note) ~= "string" or #body.note > 1024) then
            return failure(400, "version note exceeds 1024 bytes")
        end
        source = draft.value.source
    elseif body.version == registry.bundled then
        if not registry.file_plugins_enabled() then
            return failure(409, "file-based Lua plugin loading is disabled")
        end
        source = registry.builtin_source(id)
    else
        local previous, previous_err = read(key)
        if not previous then
            return failure(503, previous_err)
        end
        source = previous.value and previous.value.source
    end
    if not source then
        return failure(404, "plugin version not found")
    end
    local status, problem = validate(id, source, current.value)
    if status ~= 200 then
        return status, problem
    end
    if body.action == "publish" then
        local existing, existing_err = read(key)
        if not existing then
            return failure(503, existing_err)
        end
        if existing.value and (existing.value.source ~= source or existing.value.note ~= body.note)
        then
            return failure(409, "published versions are immutable")
        end
        version.source = source
        return publish_version(draft_key, draft, key, existing, body.note, active_key, current,
                               version)
    end
    if body.version ~= registry.bundled then
        version.source = source
    end
    return write(active_key, version, current)
end


return _M
