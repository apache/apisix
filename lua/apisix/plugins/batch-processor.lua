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
local setmetatable = setmetatable
local timer_at = ngx.timer.at
local remove = table.remove
local type = type
local huge = math.huge
local fmt = string.format
local now = ngx.now
local ngx_log = ngx.log
local DEBUG = ngx.DEBUG
local core = require("apisix.core")
local assert = assert
local Batch_Processor = {}
local Batch_Processor_mt = {
    __index = Batch_Processor
}
-- Forward function declarations
local flush
local process


-------------------------------------------------------------------------------
-- Create a timer for the `flush` operation.
-- @param self Queue
local function schedule_flush(self)
    local ok, err = timer_at(self.flush_timeout/1000, flush, self)
    if not ok then
        core.log.error("failed to create delayed flush timer: ", err)
        return
    end
    self.flush_scheduled = true
end


-------------------------------------------------------------------------------
-- Create a timer for the `process` operation.
-- @param self Batch_Processor
-- @param batch: table with `entries` and `retry_count` counter
-- @param delay number: timer delay in seconds
local function schedule_process(self, batch, delay)
    local ok, err = timer_at(delay, process, self, batch)
    if not ok then
        core.log.error("failed to create process timer: ", err)
        return
    end
end

-----------------
-- Timer handlers
-----------------


-------------------------------------------------------------------------------
-- Get the current time.
-- @return current time in seconds
local function get_now()
    return now()*1000
end


-------------------------------------------------------------------------------
-- Timer callback for triggering flush the current batch.
-- @param premature boolean: ngx.timer premature indicator
-- @param self Batch_Processor
-- @return nothing
flush = function(premature, self)
    if premature then
        return
    end

    if get_now() - self.last_activity < self.flush_timeout then
        ngx_log(DEBUG, fmt("BatchProcessor[%s] had activitity delayin the flush", self.name))
        schedule_flush(self)
        return
    end

    -- no activity and timeout reached
    ngx_log(DEBUG, fmt("BatchProcessor[%s] activating flush due to no activity, flushing triggered by flush_timeout", self.name))
    self:flush()
    self.flush_scheduled = false
end


-------------------------------------------------------------------------------
-- Timer callback for issuing the `self.process` operation
-- @param premature boolean: ngx.timer premature indicator
-- @param self Queue
-- @param batch: table with `entries` and `retry_count` counter
-- @return nothing
process = function(premature, self, batch)
    if premature then
        return
    end

    local ok, err = self.process(batch.entries)
    if ok then -- success, reset retry delays
        ngx_log(DEBUG, fmt("Batch Processor[%s] successfully processed the entries", self.name))

    else
        batch.retry_count = batch.retry_count + 1
        if batch.retry_count < self.max_retry_count then
            core.log.warn(fmt("Batch Processor[%s] failed to process entries: ", self.name), err)
            schedule_process(self, batch, self.retry_delay)
        else
            core.log.error(fmt("Batch Processor[%s] exceeded the max_retry_count[%d], dropping the entries", self.name, batch.retry_count))
        end
    end
end


---------
-- Batch Processor
---------


-------------------------------------------------------------------------------
-- Initialize a batch processor with background retryable processing
-- @param process function, invoked to process every payload generated
-- @param opts table, optionally including
-- `max_retry_count`, `flush_timeout`, `batch_max_size` and `process_delay`
-- @return table: a Queue object.
function Batch_Processor:new(process, opts)
    opts = opts or {}

    assert(type(process) == "function",
        "arg #1 (process) must be a function")
    assert(type(opts) == "table",
        "arg #2 (opts) must be a table")
    assert(opts.max_retry_count == nil or type(opts.max_retry_count) == "number",
        "max_retry_count must be a number")
    assert(opts.flush_timeout == nil or type(opts.flush_timeout) == "number",
        "flush_timeout must be a number")
    assert(opts.batch_max_size == nil or type(opts.batch_max_size) == "number",
        "batch_max_size must be a number")
    assert(opts.process_delay == nil or type(opts.process_delay) == "number",
        "process_delay must be a number")
    assert(opts.retry_delay == nil or type(opts.retry_delay) == "number",
        "retry_delay must be a number")

    local self = {
        process = process,

        -- flush timeout in milliseconds
        flush_timeout = opts.flush_timeout and opts.flush_timeout * 1000 or 5000,
        max_retry_count = opts.max_retry_count or 0,
        batch_max_size = opts.batch_max_size or 1000, -- maximum number of entries in a batch before the batch must be transmitted
        process_delay = opts.process_delay or 1,
        retry_delay = opts.retry_delay or 1,
        name = opts.name or "log buffer",

        batch_to_process = {},
        current_batch = { entries = {}, count = 0, retry_count = 0 },
        flush_scheduled = false,
        last_activity = huge,
    }

    return setmetatable(self, Batch_Processor_mt)
end


-------------------------------------------------------------------------------
-- Add data to the current batch
-- @param entry the value included in the current batch. It can be any Lua value besides nil.
-- @return true, or nil and an error message.
function Batch_Processor:add(entry)
    if entry == nil then
        return nil, "entry must be a non-nil Lua value"
    end

    if self.batch_max_size == 1 then
        -- no batching
        local batch = { entries = { entry }, retry_count = 0 }
        schedule_process(self, batch, 0)
        return true
    end

    local cb = self.current_batch
    local new_size = #cb.entries + 1
    cb.entries[new_size] = entry

    if new_size >= self.batch_max_size then
        local ok, err = self:flush()
        if not ok then
            return nil, err
        end

    elseif not self.flush_scheduled then
        schedule_flush(self)
    end

    self.last_activity = get_now()
    return true
end


-------------------------------------------------------------------------------
-- * Close the current batch and place it the processing
-- * Start a new empty batch
-- * Schedule processing if needed.
-- @return true, or nil and an error message.
function Batch_Processor:flush()
    local current_batch_size = #self.current_batch.entries

    -- Move the current batch to processing if its not empty
    if current_batch_size > 0 then
        ngx_log(DEBUG, "Moving current batch to processing, current batch size[", current_batch_size, "]")
        self.batch_to_process[#self.batch_to_process + 1] = self.current_batch
        self.current_batch = { entries = {}, retry_count = 0 }
    end

    repeat
        local oldest_batch = remove(self.batch_to_process, 1)
        schedule_process(self, oldest_batch, self.process_delay)
    until(#self.batch_to_process == 0)

    return true
end


return Batch_Processor
