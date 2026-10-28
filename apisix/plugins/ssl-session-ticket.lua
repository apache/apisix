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

--- Source adapter of the business TLS session ticket keys.
--
-- The plugin is configured only through its plugin metadata and has no request
-- phase. In both the HTTP and the Stream subsystems it watches the record,
-- validates and decrypts it on its own and publishes the result to the neutral
-- state (apisix.session_ticket.state). It never calls the SSL layer.

local core   = require("apisix.core")
local plugin = require("apisix.plugin")
local timers = require("apisix.timers")
local state  = require("apisix.session_ticket.state")
local status = require("apisix.session_ticket.status")
local record = require("apisix.plugins.ssl-session-ticket.record")
local ngx    = ngx
local type   = type
local ipairs = ipairs
local tonumber = tonumber


local plugin_name = record.name
local timer_name = "plugin#" .. plugin_name
-- how often an unchanged publishing failure is logged again
local FAILURE_LOG_INTERVAL = 60


local schema = {
    type = "object",
    properties = {},
}


local _M = {
    version = 0.1,
    priority = 1095,
    name = plugin_name,
    schema = schema,
    metadata_schema = record.metadata_schema,
    scope = "global",
}


function _M.check_schema(conf, schema_type)
    if schema_type == core.schema.TYPE_METADATA then
        -- A stored record also carries the `origin` envelope that only APISIX
        -- writes, and it is validated where it is consumed (see sync) rather
        -- than here: a record rejected here would be dropped by the config
        -- watcher, which also logs its value, and the previous keys would stay
        -- in use instead of being reported as unavailable. The Admin API checks
        -- the request body on its own.
        if type(conf) ~= "table" then
            return false, "invalid configuration"
        end

        return true
    end

    return false, "the plugin can only be configured with its plugin metadata"
end


local function weak_keyring_warning(context)
    for _, warning in ipairs(status.keyring_warnings()) do
        if warning == "encryption_disabled" then
            core.log.warn(context, ": apisix.data_encryption.enable_encrypt_fields is false, ",
                          "the TLS session ticket keys are stored in etcd in clear text")
        else
            core.log.warn(context, ": the TLS session ticket keys are encrypted with the ",
                          "default public apisix.data_encryption.keyring, ",
                          "configure a private keyring")
        end
    end
end


-- the latest revision the config watcher has caught up with: a record that is
-- absent is absent as of this revision; 0 until anything has been loaded
local function observed_revision(metadatas)
    if core.config.type == "etcd" then
        return metadatas.prev_index or 0
    end

    -- standalone: the configuration version
    return metadatas.conf_version or 0
end


local function to_candidate(value, revision)
    if value == nil then
        return {state = "empty", record = false, revision = revision}
    end

    local standalone = core.config.type ~= "etcd"
    local rec, err = record.parse(value, {standalone = standalone})
    if not rec then
        return {state = "unavailable", record = true, revision = revision, error = err}
    end

    local disabled = rec.disabled
    if standalone then
        -- nothing rewrites a standalone record, the local policy decides
        local policy = record.policy()
        disabled = disabled or not (policy and policy.enabled)
    end

    if disabled or #rec.keys == 0 then
        return {
            state = "empty",
            record = true,
            revision = revision,
            source = rec.source,
            disabled = disabled,
        }
    end

    return {
        state = "ready",
        record = true,
        revision = revision,
        source = rec.source,
        disabled = false,
        keys = rec.keys,
    }
end


-- what this process published last, so that an unchanged tick costs a single
-- read of the control record
local last_value
local last_revision
local last_ok = false
local last_err
local last_err_at = 0


local function sync()
    if ngx.worker.exiting() then
        -- a process of an older configuration must not write back
        return
    end

    local metadatas = plugin.plugin_metadatas
    if not metadatas then
        return
    end

    local observed = observed_revision(metadatas)
    if observed <= 0 then
        -- nothing loaded yet, the state stays pending
        return
    end

    local item = metadatas:get(plugin_name)
    local value = item and item.value
    local revision = value and tonumber(item.modifiedIndex) or observed

    if last_ok and value == last_value and revision == last_revision then
        local ctl = state.read_control()
        if ctl and (ctl.gate == "ready" or ctl.revision > revision) then
            return
        end
        -- a failed or pending target: retry the same input
    end

    local cand = to_candidate(value, revision)
    cand.generation = state.process_generation()

    local res, err = state.publish(cand)
    if not res then
        last_ok = false
        local now = ngx.now()
        if err ~= last_err or now - last_err_at >= FAILURE_LOG_INTERVAL then
            core.log.error("failed to publish the TLS session ticket keys of revision ",
                           revision, ": ", err)
            last_err = err
            last_err_at = now
        end
        return
    end

    last_value = value
    last_revision = revision
    last_ok = true
    last_err = nil

    if res ~= "published" then
        return
    end

    if cand.state == "unavailable" then
        core.log.error("the ", plugin_name, " record of revision ", revision,
                       " is unavailable: ", cand.error)
        return
    end

    core.log.info("published the TLS session ticket keys of revision ", revision,
                  ": ", cand.state)
    if cand.state == "ready" then
        weak_keyring_warning(plugin_name)
    end
end


function _M.init()
    timers.register_timer(timer_name, sync)

    if ngx.worker.id() ~= 0 then
        return
    end

    local role = core.table.try_read_attr(core.config.local_conf(), "deployment", "role")
    if role ~= "traditional" and role ~= "control_plane" then
        return
    end

    local policy, err = record.policy()
    if not policy then
        core.log.error(err)
        return
    end

    if policy.enabled then
        weak_keyring_warning(plugin_name)
    end
end


function _M.destroy()
    timers.unregister_timer(timer_name)
end


return _M
