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
local setmetatable = setmetatable
local timer_at = ngx.timer.at
local ipairs = ipairs
local table = table
local now = ngx.now
local type = type
local exiting = ngx.worker.exiting
local batch_processor = {}
local batch_processor_mt = {
    __index = batch_processor
}
local execute_func
local create_buffer_timer
local batch_metrics
local batch_dropped_metrics
local prometheus
if ngx.config.subsystem == "http" then
    prometheus = require("apisix.plugins.prometheus.exporter")
end


local schema = {
    type = "object",
    properties = {
        name = {type = "string", default = "log buffer"},
        max_retry_count = {type = "integer", minimum = 0, default= 0},
        retry_delay = {type = "integer", minimum = 0, default= 1},
        buffer_duration = {type = "integer", minimum = 1, default= 60},
        inactive_timeout = {type = "integer", minimum = 1, default= 5},
        batch_max_size = {type = "integer", minimum = 1, default= 1000},
        -- Upper bound, in bytes, on the data buffered by this processor
        -- (entries waiting in the buffer plus those still in-flight to the
        -- sink). When exceeded, new entries are dropped with a warning instead
        -- of being buffered. 0 (default) disables the check, preserving the
        -- previous count-only behaviour. This caps memory when entries are
        -- large (e.g. logging big response bodies) and the sink cannot keep up,
        -- which otherwise lets the in-flight backlog grow without bound. See
        -- apache/apisix#11244.
        max_buffer_bytes = {type = "integer", minimum = 0, default = 0},
    }
}
batch_processor.schema = schema


local function schedule_func_exec(self, delay, batch)
    local hdl, err = timer_at(delay, execute_func, self, batch)
    if not hdl then
        if err == "process exiting" then
            local hdl2, err2 = timer_at(0, execute_func, self, batch)
            if not hdl2 then
                core.log.error("failed to create fallback process timer ",
                               "while exiting: ", err2)
                return
            end
        else
            core.log.error("failed to create process timer: ", err)
            return
        end
    end
end


local function set_metrics(self, count)
    -- add batch metric for every route
    if batch_metrics and self.name and self.route_id and self.server_addr then
        self.label = {self.name, self.route_id, self.server_addr}
        batch_metrics:set(count, self.label)
    end
end


-- count an entry dropped because max_buffer_bytes was exceeded, so operators
-- can alert on log loss. Registered lazily (same pattern as batch_metrics) and
-- recorded even without route_id/server_addr (e.g. global rules) via fallbacks.
local function incr_dropped_metric(self)
    if not (prometheus and prometheus.get_prometheus()) then
        return
    end
    if not batch_dropped_metrics then
        batch_dropped_metrics = prometheus.get_prometheus():counter(
            "batch_process_dropped_entries",
            "dropped entries because max_buffer_bytes was exceeded",
            {"name", "route_id", "server_addr"})
    end
    batch_dropped_metrics:inc(1,
        {self.name or "", self.route_id or "", self.server_addr or ""})
end


local function slice_batch(batch, n)
    local slice = {}
    local idx = 1
    for i = n or 1, #batch do
        slice[idx] = batch[i]
        idx = idx + 1
    end
    return slice
end


-- Approximate the in-memory footprint of an entry by summing the byte length
-- of its string leaves (the dominant cost for log entries is the request /
-- response body strings). Numbers/booleans are counted as a small fixed size
-- and the walk is depth-bounded to stay cheap and cycle-safe.
local function estimate_entry_bytes(v, depth)
    local t = type(v)
    if t == "string" then
        return #v
    elseif t == "number" then
        return 8
    elseif t == "boolean" then
        return 1
    elseif t == "table" and (depth or 0) < 8 then
        local n = 0
        for k, val in pairs(v) do
            n = n + estimate_entry_bytes(k, (depth or 0) + 1)
                  + estimate_entry_bytes(val, (depth or 0) + 1)
        end
        return n
    end
    return 0
end


-- Release the bytes accounted for a batch once it leaves the buffer/in-flight
-- accounting (processed successfully or dropped). Clamped at 0 so accounting
-- drift can never make the budget reject forever.
local function release_bytes(self, bytes)
    self.buffer_bytes = self.buffer_bytes - (bytes or 0)
    if self.buffer_bytes < 0 then
        self.buffer_bytes = 0
    end
end


function execute_func(premature, self, batch)
    -- In case of "err" and a valid "first_fail" batch processor considers, all first_fail-1
    -- entries have been successfully consumed and hence reschedule the job for entries with
    -- index first_fail to #entries based on the current retry policy.
    local ok, err, first_fail = self.func(batch.entries, self.batch_max_size)
    if not ok then
        if first_fail then
            core.log.error("Batch Processor[", self.name, "] failed to process entries [",
                            #batch.entries + 1 - first_fail, "/", #batch.entries ,"]: ", err)
            batch.entries = slice_batch(batch.entries, first_fail)
            self.processed_entries = self.processed_entries + first_fail - 1
            -- the successfully consumed prefix is gone; re-account the bytes
            -- still held by the remaining (to-be-retried) entries.
            local remaining = 0
            for _, e in ipairs(batch.entries) do
                remaining = remaining + estimate_entry_bytes(e)
            end
            release_bytes(self, (batch.bytes or 0) - remaining)
            batch.bytes = remaining
        else
            core.log.error("Batch Processor[", self.name,
                           "] failed to process entries: ", err)
        end

        batch.retry_count = batch.retry_count + 1
        if batch.retry_count <= self.max_retry_count and #batch.entries > 0 then
            -- still in-flight: its bytes stay accounted until it terminates
            schedule_func_exec(self, self.retry_delay,
                               batch)
        else
            self.processed_entries = self.processed_entries + #batch.entries
            release_bytes(self, batch.bytes)
            core.log.error("Batch Processor[", self.name,"] exceeded ",
                           "the max_retry_count[", batch.retry_count,
                           "] dropping the entries")
        end
        return
    end
    self.processed_entries = self.processed_entries + #batch.entries
    release_bytes(self, batch.bytes)
    core.log.debug("Batch Processor[", self.name,
                   "] successfully processed the entries")
end


local function flush_buffer(premature, self)
    if premature or exiting() or
       now() - self.last_entry_t >= self.inactive_timeout or
       now() - self.first_entry_t >= self.buffer_duration
    then
        core.log.debug("Batch Processor[", self.name ,"] buffer ",
            "duration exceeded, activating buffer flush")
        self:process_buffer()
        self.is_timer_running = false
        return
    end

    -- buffer duration did not exceed or the buffer is active,
    -- extending the timer
    core.log.debug("Batch Processor[", self.name ,"] extending buffer timer")
    create_buffer_timer(self)
end


function create_buffer_timer(self)
    local hdl, err = timer_at(self.inactive_timeout, flush_buffer, self)
    if not hdl then
        if err == "process exiting" then
            timer_at(0, flush_buffer, self)
        else
            core.log.error("failed to create buffer timer: ", err)
            return
        end
    end
    self.is_timer_running = true
end


function batch_processor:new(func, config)
    local ok, err = core.schema.check(schema, config)
    if not ok then
        return nil, err
    end

    if type(func) ~= "function" then
        return nil, "Invalid argument, arg #1 must be a function"
    end

    core.log.debug("creating new batch processor with config: ",
        core.json.delay_encode(config, true))

    local processor = {
        func = func,
        buffer_duration = config.buffer_duration,
        inactive_timeout = config.inactive_timeout,
        max_retry_count = config.max_retry_count,
        batch_max_size = config.batch_max_size,
        retry_delay = config.retry_delay,
        name = config.name,
        max_buffer_bytes = config.max_buffer_bytes,
        batch_to_process = {},
        entry_buffer = {entries = {}, retry_count = 0, bytes = 0},
        is_timer_running = false,
        first_entry_t = 0,
        last_entry_t = 0,
        route_id = config.route_id,
        server_addr = config.server_addr,
        processed_entries = 0,
        -- bytes currently held by this processor: buffered entries plus those
        -- still in-flight to the sink. Used to enforce max_buffer_bytes.
        buffer_bytes = 0,
        dropped_entries = 0,
    }

    return setmetatable(processor, batch_processor_mt)
end

function batch_processor:push(entry)
    -- enforce the byte budget before buffering: when the data already held
    -- (buffered + in-flight) plus this entry would exceed max_buffer_bytes,
    -- drop the entry instead of letting the backlog grow without bound.
    local entry_bytes
    if self.max_buffer_bytes and self.max_buffer_bytes > 0 then
        entry_bytes = estimate_entry_bytes(entry)
        if self.buffer_bytes + entry_bytes > self.max_buffer_bytes then
            self.dropped_entries = self.dropped_entries + 1
            incr_dropped_metric(self)
            core.log.error("Batch Processor[", self.name, "] max_buffer_bytes[",
                           self.max_buffer_bytes, "] exceeded (held ", self.buffer_bytes,
                           " + entry ", entry_bytes, "), dropping entry; total dropped: ",
                           self.dropped_entries)
            return
        end
    end

    -- if the batch size is one then immediately send for processing
    if self.batch_max_size == 1 then
        self.buffer_bytes = self.buffer_bytes + (entry_bytes or 0)
        local batch = {entries = {entry}, retry_count = 0, bytes = entry_bytes or 0}
        schedule_func_exec(self, 0, batch)
        return
    end

    if prometheus and prometheus.get_prometheus() and not batch_metrics and self.name
       and self.route_id and self.server_addr then
        batch_metrics = prometheus.get_prometheus():gauge("batch_process_entries",
                                                          "batch process remaining entries",
                                                          {"name", "route_id", "server_addr"})
    end

    local entries = self.entry_buffer.entries
    table.insert(entries, entry)
    self.buffer_bytes = self.buffer_bytes + (entry_bytes or 0)
    self.entry_buffer.bytes = self.entry_buffer.bytes + (entry_bytes or 0)
    set_metrics(self, #entries)

    if #entries == 1 then
        self.first_entry_t = now()
    end
    self.last_entry_t = now()

    if self.batch_max_size <= #entries then
        core.log.debug("Batch Processor[", self.name ,
                       "] batch max size has exceeded")
        self:process_buffer()
    end

    if not self.is_timer_running then
        create_buffer_timer(self)
    end
end


function batch_processor:process_buffer()
    -- If entries are present in the buffer move the entries to processing
    if #self.entry_buffer.entries > 0 then
        core.log.debug("transferring buffer entries to processing pipe line, ",
            "buffercount[", #self.entry_buffer.entries ,"]")
        self.batch_to_process[#self.batch_to_process + 1] = self.entry_buffer
        self.entry_buffer = {entries = {}, retry_count = 0, bytes = 0}
        set_metrics(self, 0)
    end

    for _, batch in ipairs(self.batch_to_process) do
        schedule_func_exec(self, 0, batch)
    end

    self.batch_to_process = {}
end


return batch_processor
