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
local batch_processor = require("apisix.utils.batch-processor")
local timer_at = ngx.timer.at
local pairs = pairs
local setmetatable = setmetatable


local _M = {}
local mt = { __index = _M }


function _M.new(name)
    return setmetatable({
        stale_timer_running = false,
        buffers = {},
        total_pushed_entries = 0,
        name = name,
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


-- remove stale objects from the memory after timer expires
local function remove_stale_objects(premature, self)
    if premature then
        return
    end

    for key, batch in pairs(self.buffers) do
        if #batch.entry_buffer.entries == 0 and #batch.batch_to_process == 0 then
            core.log.info("removing batch processor stale object, conf: ",
                          core.json.delay_encode(key))
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
    local processed_entries = 0
    for _, log_buffer in pairs(self.buffers) do
        processed_entries = processed_entries + log_buffer.processed_entries
    end
    return processed_entries
end

function _M:add_entry(conf, entry, max_pending_entries)
    if max_pending_entries then
        local total_processed_entries_count = total_processed_entries(self)
        if self.total_pushed_entries - total_processed_entries_count > max_pending_entries then
            core.log.error("max pending entries limit exceeded. discarding entry.",
                           " total_pushed_entries: ", self.total_pushed_entries,
                           " total_processed_entries: ", total_processed_entries_count,
                           " max_pending_entries: ", max_pending_entries)
            return
        end
    end
    check_stale(self)

    local log_buffer = self.buffers[conf]
    if not log_buffer then
        return false
    end

    log_buffer:push(entry)
    self.total_pushed_entries = self.total_pushed_entries + 1
    return true
end


function _M:add_entry_to_new_processor(conf, entry, ctx, func, max_pending_entries)
    if max_pending_entries then
        local total_processed_entries_count = total_processed_entries(self)
        if self.total_pushed_entries - total_processed_entries_count > max_pending_entries then
            core.log.error("max pending entries limit exceeded. discarding entry.",
                           " total_pushed_entries: ", self.total_pushed_entries,
                           " total_processed_entries: ", total_processed_entries_count,
                           " max_pending_entries: ", max_pending_entries)
            return
        end
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
    self.buffers[conf] = log_buffer
    self.total_pushed_entries = self.total_pushed_entries + 1
    return true
end


return _M
