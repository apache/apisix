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
local plugin = require("apisix.plugin")
local batch_processor = require("apisix.utils.batch-processor")
local timer_at = ngx.timer.at
local now = ngx.now
local pairs = pairs
local setmetatable = setmetatable


-- A pending entry keeps a whole log payload alive, including the request and
-- response bodies when body logging is on, so a log server that is slow or
-- unreachable turns the backlog into unbounded worker memory. Cap it by default;
-- the batch-processor documentation records what the cap costs per body size.
local DEFAULT_MAX_PENDING_ENTRIES = 8192
-- Logging one line per discarded entry would itself become a flood during the very
-- outage that causes the discards, so report a summary at most this often, in seconds.
local DISCARD_LOG_INTERVAL = 1


local _M = {}
local mt = { __index = _M }


-- `name` labels the batch processor in logs and metrics and is not necessarily the
-- plugin's name; `plugin_name` names the plugin whose metadata carries
-- `max_pending_entries`, and defaults to `name`.
function _M.new(name, plugin_name)
    return setmetatable({
        stale_timer_running = false,
        buffers = {},
        total_pushed_entries = 0,
        total_stale_processed_entries = 0,
        processed_entries_snapshot = 0,
        discarded_entries = 0,
        last_discard_log_time = 0,
        name = name,
        plugin_name = plugin_name or name,
    }, mt)
end


function _M:wrap_schema(schema)
    local bp_schema = core.table.deepcopy(batch_processor.schema)
    local properties = schema.properties
    for k, v in pairs(bp_schema.properties) do
        if not properties[k] then
            properties[k] = v
        end
        -- don't touch if the plugin overrides the property
    end

    properties.name.default = self.name
    return schema
end


-- Every batch-processor based logger exposes the same backlog limit, so declare it
-- here instead of repeating it in each plugin's metadata schema.
function _M:wrap_metadata_schema(schema)
    schema.properties.max_pending_entries = {
        type = "integer",
        minimum = 1,
        default = DEFAULT_MAX_PENDING_ENTRIES,
        description = "maximum number of entries waiting to be processed; new "
                   .. "entries are discarded while the backlog exceeds it",
    }
    return schema
end


-- remove stale objects from the memory after timer expires
local function remove_stale_objects(premature, self)
    if premature then
        return
    end

    for key, batch in pairs(self.buffers) do
        if #batch.entry_buffer.entries == 0 and #batch.batch_to_process == 0 then
            core.log.info("removing batch processor stale object, conf: ",
                          core.json.delay_encode(key))
            self.total_stale_processed_entries =
                self.total_stale_processed_entries + batch.processed_entries
           self.buffers[key] = nil
        end
    end

    self.stale_timer_running = false
end


local check_stale
do
    local interval = 1800

    function check_stale(self)
        if not self.stale_timer_running then
            -- run the timer every 30 mins if any log is present
            timer_at(interval, remove_stale_objects, self)
            self.stale_timer_running = true
        end
    end

    function _M.set_check_stale_interval(time)
        interval = time
    end
end


local function total_processed_entries(self)
    local processed_entries = self.total_stale_processed_entries
    for _, log_buffer in pairs(self.buffers) do
        processed_entries = processed_entries + log_buffer.processed_entries
    end
    return processed_entries
end


local function max_pending_entries(self)
    local metadata = plugin.plugin_metadata(self.plugin_name)
    return metadata and metadata.value and metadata.value.max_pending_entries
           or DEFAULT_MAX_PENDING_ENTRIES
end


-- The processed count only ever grows, so the last one we read is a lower bound on
-- the current one, and `pushed - snapshot` is therefore an upper bound on the
-- backlog. While that bound is under the limit the backlog certainly is too, which
-- keeps the common path off the per-buffer walk: the walk only happens once the
-- bound catches up with the limit, roughly once every `max_pending_entries` entries.
local function backlog_is_full(self, limit)
    if self.total_pushed_entries - self.processed_entries_snapshot < limit then
        return false
    end

    self.processed_entries_snapshot = total_processed_entries(self)
    return self.total_pushed_entries - self.processed_entries_snapshot >= limit
end


local function report_discard(self, limit)
    self.discarded_entries = self.discarded_entries + 1

    local time = now()
    if time - self.last_discard_log_time < DISCARD_LOG_INTERVAL then
        return
    end

    core.log.error("max pending entries limit exceeded. discarding entry.",
                   " total_pushed_entries: ", self.total_pushed_entries,
                   " total_processed_entries: ", self.processed_entries_snapshot,
                   " max_pending_entries: ", limit,
                   " discarded_entries: ", self.discarded_entries)
    self.last_discard_log_time = time
    self.discarded_entries = 0
end


function _M:add_entry(conf, entry)
    local limit = max_pending_entries(self)
    if backlog_is_full(self, limit) then
        report_discard(self, limit)
        return
    end
    check_stale(self)

    local log_buffer = self.buffers[plugin.conf_version(conf)]
    if not log_buffer then
        return false
    end

    log_buffer:push(entry)
    self.total_pushed_entries = self.total_pushed_entries + 1
    return true
end


function _M:add_entry_to_new_processor(conf, entry, ctx, func)
    -- Callers reach this only after add_entry() declined, so a discarded entry has
    -- already been counted and reported there; re-check the backlog so a direct
    -- caller is still bounded, but do not count the same entry a second time.
    if backlog_is_full(self, max_pending_entries(self)) then
        return
    end
    check_stale(self)

    local config = {
        name = conf.name,
        batch_max_size = conf.batch_max_size,
        max_retry_count = conf.max_retry_count,
        retry_delay = conf.retry_delay,
        buffer_duration = conf.buffer_duration,
        inactive_timeout = conf.inactive_timeout,
        route_id = ctx.var.route_id,
        server_addr = ctx.var.server_addr,
    }

    local log_buffer, err = batch_processor:new(func, config)
    if not log_buffer then
        core.log.error("error when creating the batch processor: ", err)
        return false
    end

    log_buffer:push(entry)
    self.buffers[plugin.conf_version(conf)] = log_buffer
    self.total_pushed_entries = self.total_pushed_entries + 1
    return true
end


return _M
