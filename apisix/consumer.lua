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
local core           = require("apisix.core")
local config_local   = require("apisix.core.config_local")
local secret         = require("apisix.secret")
local plugin         = require("apisix.plugin")
local plugin_checker = require("apisix.plugin").plugin_checker
local check_schema   = require("apisix.core.schema").check
local error          = error
local ipairs         = ipairs
local pairs          = pairs
local type           = type
local string_sub     = string.sub
local consumers


local _M = {
    version = 0.3,
}

local lrucache = core.lrucache.new({
    ttl = 300, count = 512
})

-- Please calculate and set the value of the "consumers_count_for_lrucache"
-- variable based on the number of consumers in the current environment,
-- taking into account the appropriate adjustment coefficient.
local consumers_count_for_lrucache = 4096

local function remove_etcd_prefix(key)
    local prefix = ""
    local local_conf = config_local.local_conf()
    local role = core.table.try_read_attr(local_conf, "deployment", "role")
    local provider = core.table.try_read_attr(local_conf, "deployment", "role_" ..
    role, "config_provider")
    if provider == "etcd" and local_conf.etcd and local_conf.etcd.prefix then
        prefix = local_conf.etcd.prefix
    end
    return string_sub(key, #prefix + 1)
end

-- /{etcd.prefix}/consumers/{consumer_name}/credentials/{credential_id} --> {consumer_name}
local function get_consumer_name_from_credential_etcd_key(key)
    local uri_segs = core.utils.split_uri(remove_etcd_prefix(key))
    return uri_segs[3]
end

local function is_credential_etcd_key(key)
    if not key then
        return false
    end

    local uri_segs = core.utils.split_uri(remove_etcd_prefix(key))
    return uri_segs[2] == "consumers" and uri_segs[4] == "credentials"
end

local function get_credential_id_from_etcd_key(key)
    local uri_segs = core.utils.split_uri(remove_etcd_prefix(key))
    return uri_segs[5]
end

local function filter_consumers_list(data_list)
    if #data_list == 0 then
        return data_list
    end

    local list = {}
    for _, item in ipairs(data_list) do
        if not (type(item) == "table" and is_credential_etcd_key(item.key)) then
            core.table.insert(list, item)
        end
    end

    return list
end

local plugin_consumer
local construct_consumer_data
do
    local consumers_id_lrucache = core.lrucache.new({
            count = consumers_count_for_lrucache
        })

function construct_consumer_data(val, name, plugin_config)
    -- if the val is a Consumer, clone it to the local consumer;
    -- if the val is a Credential, to get the Consumer by consumer_name and then clone
    -- it to the local consumer.
    local consumer
    if is_credential_etcd_key(val.key) then
        local consumer_name = get_consumer_name_from_credential_etcd_key(val.key)
        local the_consumer = consumers:get(consumer_name)
        if the_consumer and the_consumer.value then
            consumer = consumers_id_lrucache(val.value.id .. name, val.modifiedIndex..
                                                the_consumer.modifiedIndex,
                function (val, the_consumer)
                    consumer = core.table.clone(the_consumer.value)
                    consumer.modifiedIndex = the_consumer.modifiedIndex
                    consumer.credential_id = get_credential_id_from_etcd_key(val.key)
                    return consumer
                end, val, the_consumer)
        else
            -- Normally wouldn't get here:
            -- it should belong to a consumer for any credential.
            return nil, "failed to get the consumer for the credential,",
                " a wild credential has appeared!",
                " credential key: ", val.key, ", consumer name: ", consumer_name
        end
    else
        consumer = consumers_id_lrucache(val.value.id .. name, val.modifiedIndex,
            function (val)
                consumer = core.table.clone(val.value)
                consumer.modifiedIndex = val.modifiedIndex
                return consumer
            end, val)
    end

    -- if the consumer has labels, set the field custom_id to it.
    -- the custom_id is used to set in the request headers to the upstream.
    if consumer.labels then
        consumer.custom_id = consumer.labels["custom_id"]
    end

    -- Note: the id here is the key of consumer data, which
    -- is 'username' field in admin
    consumer.consumer_name = consumer.id
    consumer.auth_conf = plugin_config

    return consumer
end


function plugin_consumer()
    local plugins = {}

    if consumers.values == nil then
        return plugins
    end

    -- consumers.values is the list that got from etcd by prefix key {etcd_prefix}/consumers.
    -- So it contains consumers and credentials.
    -- The val in the for-loop may be a Consumer or a Credential.
    for _, val in ipairs(consumers.values) do
        if type(val) ~= "table" then
            goto CONTINUE
        end

        for name, config in pairs(val.value.plugins or {}) do
            local plugin_obj = plugin.get(name)
            if plugin_obj and plugin_obj.type == "auth" then
                if not plugins[name] then
                    plugins[name] = {
                        nodes = {},
                        len = 0,
                        conf_version = consumers.conf_version
                    }
                end

                local consumer, err = construct_consumer_data(val, name, config)
                if not consumer then
                    core.log.error("failed to construct consumer data for plugin ",
                                   name, ": ", err)
                    goto CONTINUE
                end

                plugins[name].len = plugins[name].len + 1
                core.table.insert(plugins[name].nodes, plugins[name].len,
                                    consumer)
            end
        end

        ::CONTINUE::
    end

    return plugins
end

end


-- Incremental consumer plugin tree rebuild.
-- Instead of rebuilding the full O(N) tree on every conf_version change,
-- only process consumers that were created/updated/deleted.
-- Full rebuild runs only on bootstrap (first request).
-- A background timer runs a lightweight consistency check every 30s:
-- it compares tracked IDs against consumers.values without reconstructing data.
-- Only triggers a full rebuild if it finds stale entries (extremely rare).
-- Motivation: stock APISIX rebuilds this whole O(N) tree on every conf_version change.

local cached_plugins
local cached_conf_version = 0
local node_index = {}           -- "plugin\0eid" -> position in nodes array
local entry_plugins = {}        -- eid -> { [plugin_name] = true }
local pending_set = {}          -- eid -> consumer item (from filter callback)
local has_pending = false
local pending_delete = false    -- a delete event was seen; reconcile removed ids
local tracked_count = 0         -- count of consumers.values at last sync
local FULL_SYNC_INTERVAL = 30   -- seconds between background consistency checks

-- key-auth (and the other auth plugins) look consumers up by a key value, not by
-- position, via _M.consumers_kv() -> a per-plugin {key_value -> consumer} map.
-- That map was rebuilt in full on every conf_version change (O(N) over all
-- consumers, each cloned through a fill lru). We instead maintain it incrementally
-- alongside the node arrays: kv_upsert on add/update, kv_remove on delete. The
-- map lives on the per-plugin data table (pd.kv) and is populated lazily on the
-- first lookup (which also teaches us pd.key_attr for that plugin).
local function kv_upsert(pd, consumer)
    if not pd.kv or not pd.key_attr then
        return
    end
    local nc = core.table.clone(consumer)
    nc.auth_conf = secret.fetch_secrets(nc.auth_conf, false)
    -- fail closed: skip unset credentials or unresolved secret refs so a client
    -- can never authenticate with a literal "$ENV://..." reference string.
    if secret.has_secret_ref(nc.auth_conf) then
        return
    end
    local key_value = nc.auth_conf[pd.key_attr]
    if key_value == nil then
        return
    end
    pd.kv[key_value] = nc
    consumer._kvkey = key_value
end

local function kv_remove(pd, consumer)
    if pd.kv and consumer and consumer._kvkey ~= nil then
        pd.kv[consumer._kvkey] = nil
    end
end

-- Collect current consumer/credential IDs from consumers.values.
local function collect_current_ids()
    local ids = {}
    for _, val in ipairs(consumers.values or {}) do
        if type(val) == "table" and val.value and val.value.id then
            ids[val.value.id] = true
        end
    end
    return ids
end

-- Remove all plugin node entries for a given consumer/credential ID.
-- Uses swap-with-last for O(1) array removal without holes.
local function remove_consumer_entries(eid)
    local pset = entry_plugins[eid]
    if not pset then return end
    for pname in pairs(pset) do
        local pd = cached_plugins[pname]
        if pd then
            local key = pname .. "\0" .. eid
            local pos = node_index[key]
            if pos and pos <= pd.len then
                kv_remove(pd, pd.nodes[pos])
                if pos < pd.len then
                    -- swap with last element
                    local last = pd.nodes[pd.len]
                    pd.nodes[pos] = last
                    node_index[pname .. "\0" .. last._eid] = pos
                end
                pd.nodes[pd.len] = nil
                pd.len = pd.len - 1
            end
            node_index[key] = nil
        end
    end
    entry_plugins[eid] = nil
end

-- Add a consumer/credential to the appropriate auth plugin nodes.
local function add_consumer_entry(val)
    if type(val) ~= "table" or not val.value then return end
    local eid = val.value.id
    if not eid then return end
    for name, config in pairs(val.value.plugins or {}) do
        local plugin_obj = plugin.get(name)
        if not plugin_obj or plugin_obj.type ~= "auth" then
            goto next_plugin
        end
        if not cached_plugins[name] then
            cached_plugins[name] = {
                nodes = {}, len = 0,
                conf_version = consumers.conf_version
            }
        end
        local consumer, err = construct_consumer_data(val, name, config)
        if not consumer then
            core.log.error("incremental: failed to construct consumer for plugin ",
                           name, ": ", err)
            goto next_plugin
        end
        consumer._eid = eid
        local pd = cached_plugins[name]
        pd.len = pd.len + 1
        pd.nodes[pd.len] = consumer
        node_index[name .. "\0" .. eid] = pd.len
        if not entry_plugins[eid] then entry_plugins[eid] = {} end
        entry_plugins[eid][name] = true
        kv_upsert(pd, consumer)
        ::next_plugin::
    end
end

-- Full rebuild: construct entire tree and build indexes from scratch.
local function full_rebuild()
    cached_plugins = plugin_consumer()
    node_index = {}
    entry_plugins = {}
    for pname, pd in pairs(cached_plugins) do
        for i = 1, pd.len do
            local c = pd.nodes[i]
            local eid = c.credential_id or c.consumer_name
            c._eid = eid
            node_index[pname .. "\0" .. eid] = i
            if not entry_plugins[eid] then entry_plugins[eid] = {} end
            entry_plugins[eid][pname] = true
        end
    end
    tracked_count = consumers.values and #consumers.values or 0
    cached_conf_version = consumers.conf_version
    core.table.clear(pending_set)
    has_pending = false
    pending_delete = false
    core.log.info("consumer plugin tree fully rebuilt, conf_version: ",
                  cached_conf_version, ", tracked: ", tracked_count)
end

-- Incremental update: process only pending changes, then verify for deletes.
local function apply_incremental()
    -- Process pending upserts from filter callback
    for eid, val in pairs(pending_set) do
        remove_consumer_entries(eid)
        add_consumer_entry(val)
    end
    core.table.clear(pending_set)

    -- Deletes arrive as value-less events; the watch does not hand us an id we
    -- can map to an auth entry (consumer vs credential), so when a delete was
    -- flagged we reconcile the incremental index against the current id set.
    -- This is an O(N) id scan with NO consumer-data construction (the expensive
    -- part), so it stays cheap even with a large consumer base, and it runs only
    -- when a delete actually happened -- independent of whether the net count
    -- went down (e.g. creates and deletes interleaved under churn).
    if pending_delete then
        local cur_ids = collect_current_ids()
        -- Collect first, then remove (can't modify entry_plugins during pairs iteration)
        local to_remove = {}
        for eid in pairs(entry_plugins) do
            if not cur_ids[eid] then
                to_remove[#to_remove + 1] = eid
            end
        end
        for _, eid in ipairs(to_remove) do
            remove_consumer_entries(eid)
        end
        pending_delete = false
    end

    has_pending = false
    tracked_count = consumers.values and #consumers.values or 0

    -- Update conf_version on all plugin data; keep the (incrementally maintained)
    -- key_value map version in lockstep so _M.consumers_kv() serves it without a
    -- full rebuild.
    for _, pd in pairs(cached_plugins) do
        pd.conf_version = consumers.conf_version
        if pd.kv then
            pd.kv_version = consumers.conf_version
        end
    end
    cached_conf_version = consumers.conf_version
end


_M.filter_consumers_list = filter_consumers_list

function _M.get_consumer_key_from_credential_key(key)
    local uri_segs = core.utils.split_uri(key)
    return "/consumers/" .. uri_segs[3]
end

function _M.plugin(plugin_name)
    if not cached_plugins then
        full_rebuild()
    elseif cached_conf_version ~= consumers.conf_version then
        apply_incremental()
    end
    return cached_plugins[plugin_name]
end

function _M.consumers_conf(plugin_name)
    return _M.plugin(plugin_name)
end


-- attach chosen consumer to the ctx, used in auth plugin
function _M.attach_consumer(ctx, consumer, conf)
    ctx.consumer = consumer
    ctx.consumer_name = consumer.consumer_name
    ctx.consumer_group_id = consumer.group_id
    ctx.consumer_ver = conf.conf_version

    core.request.set_header(ctx, "X-Consumer-Username", consumer.username)
    core.request.set_header(ctx, "X-Credential-Identifier", consumer.credential_id)
    core.request.set_header(ctx, "X-Consumer-Custom-ID", consumer.custom_id)
end


function _M.consumers()
    if not consumers then
        return nil, nil
    end

    return filter_consumers_list(consumers.values), consumers.conf_version
end


local create_consume_cache
do
    local consumer_lrucache = core.lrucache.new({
            count = consumers_count_for_lrucache
        })

local function fill_consumer_secret(consumer)
    local new_consumer = core.table.clone(consumer)
    new_consumer.auth_conf = secret.fetch_secrets(new_consumer.auth_conf, false)
    return new_consumer
end


function create_consume_cache(consumers_conf, key_attr)
    local consumer_names = {}

    for _, consumer in ipairs(consumers_conf.nodes) do
        local new_consumer = consumer_lrucache(consumer, nil,
                                fill_consumer_secret, consumer)
        local key_value = new_consumer.auth_conf[key_attr]
        -- fail closed: skip if the credential is unset or an unresolved secret ref,
        -- else a client could auth with the literal $ENV://... reference string
        if key_value == nil then
            core.log.error("missing consumer auth credential '", key_attr,
                           "', skipping consumer: ", new_consumer.consumer_name)

        elseif secret.has_secret_ref(new_consumer.auth_conf) then
            core.log.error("failed to resolve secret reference in consumer auth ",
                           "credential, skipping consumer: ", new_consumer.consumer_name)

        else
            consumer_names[key_value] = new_consumer
            -- Record the key on the node so an incremental delete/update can
            -- remove this entry from the map (kv_remove). Nodes added later go
            -- through kv_upsert which sets this too; setting it here covers the
            -- nodes that were in the initial/full build.
            consumer._kvkey = key_value
        end
    end

    return consumer_names
end

end


function _M.consumers_kv(plugin_name, consumer_conf, key_attr)
    -- consumer_conf is the per-plugin node set from _M.plugin(); the key_value ->
    -- consumer map is cached on it and maintained incrementally by kv_upsert/
    -- kv_remove, so it is not rebuilt on every conf_version change. Rebuild only on
    -- first use, a key_attr change, or a version gap the incremental path missed.
    if consumer_conf.kv and consumer_conf.key_attr == key_attr
       and consumer_conf.kv_version == consumer_conf.conf_version then
        return consumer_conf.kv
    end

    consumer_conf.kv = create_consume_cache(consumer_conf, key_attr)
    consumer_conf.key_attr = key_attr
    consumer_conf.kv_version = consumer_conf.conf_version
    return consumer_conf.kv
end


function _M.find_consumer(plugin_name, key, key_value)
    local consumer
    local consumer_conf
    consumer_conf = _M.plugin(plugin_name)
    if not consumer_conf then
        return nil, nil, "Missing related consumer"
    end
    local consumers = _M.consumers_kv(plugin_name, consumer_conf, key)
    consumer = consumers[key_value]
    return consumer, consumer_conf
end


local function check_consumer(consumer, key)
    local data_valid
    local err
    if is_credential_etcd_key(key) then
        data_valid, err = check_schema(core.schema.credential, consumer)
    else
        data_valid, err = check_schema(core.schema.consumer, consumer)
    end
    if not data_valid then
        return data_valid, err
    end

    return plugin_checker(consumer, core.schema.TYPE_CONSUMER)
end


local function filter(consumer)
    -- A delete arrives as a value-less event (the etcd watch sets value = nil on
    -- removal). Flag it so the next incremental apply reconciles removed ids and
    -- the deleted consumer stops authenticating on the next request.
    if not consumer.value then
        if cached_plugins then
            pending_delete = true
            has_pending = true
        end
        return
    end

    if not consumer.value.plugins then
        return
    end
    plugin.set_plugins_meta_parent(consumer.value.plugins, consumer)

    -- Track changed consumer for incremental rebuild
    if cached_plugins and consumer.value.id then
        pending_set[consumer.value.id] = consumer
        has_pending = true
    end
end


-- Background consistency check: lightweight scan to detect stale entries.
-- Only triggers a full rebuild if an actual discrepancy is found.
-- This avoids the O(N) construction cost of plugin_consumer() on every tick.
local function background_full_rebuild(premature)
    if premature then return end
    if not consumers or not consumers.values then return end
    if not cached_plugins then return end

    -- Process any pending changes first
    if has_pending then
        apply_incremental()
    end

    -- Quick count check
    local cur_count = #consumers.values
    if cur_count ~= tracked_count then
        core.log.info("background: count mismatch (tracked=", tracked_count,
                      ", actual=", cur_count, "), full rebuild")
        full_rebuild()
        return
    end

    -- Deep consistency check: look for stale entries in our index.
    -- This catches the rare simultaneous create+delete case where
    -- count stays the same but different consumers are present.
    local cur_ids = collect_current_ids()
    for eid in pairs(entry_plugins) do
        if not cur_ids[eid] then
            core.log.warn("background: stale entry ", eid, " detected, full rebuild")
            full_rebuild()
            return
        end
    end
end


function _M.init_worker()
    local err
    local cfg = {
        automatic = true,
        checker = check_consumer,
        filter = filter
    }

    consumers, err = core.config.new("/consumers", cfg)
    if not consumers then
        error("failed to create etcd instance for fetching consumers: " .. err)
        return
    end

    local ok, timer_err = ngx.timer.every(FULL_SYNC_INTERVAL, background_full_rebuild)
    if not ok then
        core.log.error("failed to create consumer full rebuild timer: ", timer_err)
    end
end

local function get_anonymous_consumer_from_local_cache(name)
    local anon_consumer_raw = consumers:get(name)

    if not anon_consumer_raw or not anon_consumer_raw.value or
    not anon_consumer_raw.value.id or not anon_consumer_raw.modifiedIndex then
        return nil, nil, "failed to get anonymous consumer " .. name
    end

    -- make structure of anon_consumer similar to that of consumer_mod.consumers_kv's response
    local anon_consumer = anon_consumer_raw.value
    anon_consumer.consumer_name = anon_consumer_raw.value.id
    anon_consumer.modifiedIndex = anon_consumer_raw.modifiedIndex

    local anon_consumer_conf = {
        conf_version = anon_consumer_raw.modifiedIndex
    }

    return anon_consumer, anon_consumer_conf
end


function _M.get_anonymous_consumer(name)
    local anon_consumer, anon_consumer_conf, err
    anon_consumer, anon_consumer_conf, err = get_anonymous_consumer_from_local_cache(name)

    return anon_consumer, anon_consumer_conf, err
end


return _M
