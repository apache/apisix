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
local timer_every = ngx.timer.every
local pairs = pairs
local ipairs = ipairs
local table = table
local now = ngx.now
local type = type
local xpcall = xpcall
local tostring = tostring
local debug_traceback = debug.traceback
local exiting = ngx.worker.exiting
local batch_processor = {}
local batch_processor_mt = {
    __index = batch_processor
}
local execute_func
local create_buffer_timer
local recover_timers
local batch_metrics
local prometheus
if ngx.config.subsystem == "http" then
    prometheus = require("apisix.plugins.prometheus.exporter")
end


-- One worker-wide recurring timer recovers callbacks that OpenResty silently drops
-- at lua_max_running_timers. Unlike an at() chain, every() schedules its next tick
-- before checking the running-timer limit, so recovery survives the same pressure.
local RECOVERY_INTERVAL = 1
local TIMER_GRACE = 1
local recovery_timer_running = false
local pending_batches = {}
local pending_buffers = {}


local function ensure_recovery_timer()
    if recovery_timer_running or exiting() then
        return
    end

    local ok, err = timer_every(RECOVERY_INTERVAL, recover_timers)
    if not ok then
        core.log.error("failed to create batch recovery timer: ", err)
        return
    end
    recovery_timer_running = true
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
    }
}
batch_processor.schema = schema


-- The backlog limit in batch-processor-manager counts an entry as pending until it
-- is added to processed_entries, so every batch that is given up on, not only the
-- ones that ran, must be added; otherwise it stays pending for the worker's lifetime.
local function drop_batch(self, batch)
    self.processed_entries = self.processed_entries + #batch.entries
end


local function schedule_func_exec(self, delay, batch)
    ensure_recovery_timer()
    local hdl, err = timer_at(delay, execute_func, self, batch)
    if not hdl then
        if err == "process exiting" then
            local hdl2, err2 = timer_at(0, execute_func, self, batch)
            if not hdl2 then
                core.log.error("failed to create fallback process timer ",
                               "while exiting: ", err2, ", dropped entries: ",
                               #batch.entries)
                drop_batch(self, batch)
                return
            end
            delay = 0
        else
            core.log.error("failed to create process timer: ", err,
                           ", dropped entries: ", #batch.entries)
            drop_batch(self, batch)
            return
        end
    end

    batch.timer_deadline = now() + delay
    pending_batches[batch] = self
end


local function set_metrics(self, count)
    -- add batch metric for every route
    if batch_metrics and self.name and self.route_id and self.server_addr then
        self.label = {self.name, self.route_id, self.server_addr}
        batch_metrics:set(count, self.label)
    end
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


function execute_func(premature, self, batch)
    -- A late callback must not send or account for an already recovered batch.
    if pending_batches[batch] ~= self then
        return
    end
    pending_batches[batch] = nil
    batch.timer_deadline = nil

    -- Remove the deadline before invoking user code, which may yield for longer
    -- than the grace period while a logger is sending or retrying a request.
    -- In case of "err" and a valid "first_fail" batch processor considers, all first_fail-1
    -- entries have been successfully consumed and hence reschedule the job for entries with
    -- index first_fail to #entries based on the current retry policy.
    local call_ok, ok, err, first_fail = xpcall(self.func, debug_traceback,
                                                batch.entries, self.batch_max_size)
    if not call_ok then
        -- a callback that raises has failed the batch, so it takes the same retry
        -- and drop path as one that returns false; "runtime error" is what the log
        -- said when the raise used to abort the timer
        ok, err, first_fail = false, "runtime error: " .. tostring(ok), nil
    end

    -- err goes through tostring: ngx.log raises on a table without __tostring, and a
    -- raise here would end the timer before the batch is counted
    if not ok then
        if first_fail then
            core.log.error("Batch Processor[", self.name, "] failed to process entries [",
                            #batch.entries + 1 - first_fail, "/", #batch.entries ,"]: ",
                            tostring(err))
            batch.entries = slice_batch(batch.entries, first_fail)
            self.processed_entries = self.processed_entries + first_fail - 1
        else
            core.log.error("Batch Processor[", self.name,
                           "] failed to process entries: ", tostring(err))
        end

        batch.retry_count = batch.retry_count + 1
        if batch.retry_count <= self.max_retry_count and #batch.entries > 0 then
            schedule_func_exec(self, self.retry_delay,
                               batch)
        else
            drop_batch(self, batch)
            core.log.error("Batch Processor[", self.name,"] exceeded ",
                           "the max_retry_count[", batch.retry_count,
                           "] dropping the entries")
        end
        return
    end
    self.processed_entries = self.processed_entries + #batch.entries
    core.log.debug("Batch Processor[", self.name,
                   "] successfully processed the entries")
end


local function flush_buffer(premature, self, timer)
    if pending_buffers[self] ~= timer then
        return
    end
    pending_buffers[self] = nil

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
    ensure_recovery_timer()
    local timer = {deadline = now() + self.inactive_timeout}
    local hdl, err = timer_at(self.inactive_timeout, flush_buffer, self, timer)
    if not hdl then
        if err == "process exiting" then
            hdl, err = timer_at(0, flush_buffer, self, timer)
            timer.deadline = now()
        end
        if not hdl then
            self.is_timer_running = false
            core.log.error("failed to create buffer timer: ", err)
            return
        end
    end
    pending_buffers[self] = timer
    self.is_timer_running = true
end


function recover_timers(premature)
    if premature then
        return
    end

    local cutoff = now() - TIMER_GRACE
    local dropped = {}
    for batch, self in pairs(pending_batches) do
        if batch.timer_deadline <= cutoff then
            pending_batches[batch] = nil
            batch.timer_deadline = nil
            local count = #batch.entries
            self.processed_entries = self.processed_entries + count
            dropped[self] = (dropped[self] or 0) + count
        end
    end
    -- Aggregate the report so recovering a full backlog does not flood the log.
    for self, count in pairs(dropped) do
        core.log.error("Batch Processor[", self.name, "] dropping ", count,
                       " entries whose process timers did not start")
    end

    local buffers = {}
    for self, timer in pairs(pending_buffers) do
        if timer.deadline <= cutoff then
            buffers[#buffers + 1] = self
        end
    end
    -- Flushing may rearm a buffer timer, so do it outside the registry traversal.
    for _, self in ipairs(buffers) do
        core.log.warn("Batch Processor[", self.name, "] recovering buffer timer")
        flush_buffer(false, self, pending_buffers[self])
    end
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
        batch_to_process = {},
        entry_buffer = {entries = {}, retry_count = 0},
        is_timer_running = false,
        first_entry_t = 0,
        last_entry_t = 0,
        route_id = config.route_id,
        server_addr = config.server_addr,
        pushed_entries = 0,
        processed_entries = 0
    }

    return setmetatable(processor, batch_processor_mt)
end

function batch_processor:push(entry)
    self.pushed_entries = self.pushed_entries + 1

    -- if the batch size is one then immediately send for processing
    if self.batch_max_size == 1 then
        local batch = {entries = {entry}, retry_count = 0}
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
        self.entry_buffer = {entries = {}, retry_count = 0}
        set_metrics(self, 0)
    end

    for _, batch in ipairs(self.batch_to_process) do
        schedule_func_exec(self, 0, batch)
    end

    self.batch_to_process = {}
end


return batch_processor
