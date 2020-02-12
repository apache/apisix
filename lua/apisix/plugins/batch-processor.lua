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
local remove = table.remove
local fmt = string.format
local ngx_log = ngx.log
local DEBUG = ngx.DEBUG
local table = table
local now = ngx.now
local type = type
local Batch_Processor = {}
local Batch_Processor_mt = {
    __index = Batch_Processor
}
local execute_func
local create_buffer_timer


local schema = {
    type = "object",
    properties = {
        name = {type = "string", default = "log buffer"},
        max_retry_count = {type = "integer", minimum = 0, default= 0},
        retry_delay = {type = "integer", minimum = 0, default= 1},
        buffer_duration = {type = "integer", minimum = 1, default= 60}, -- maximum age in seconds of the oldest log item in a batch before the batch must be transmitted
        inactive_timeout = {type = "integer", minimum = 1, default= 5}, -- maximum age in seconds when the buffer will be flushed if inactive
        batch_max_size = {type = "integer", minimum = 1, default= 1000}, -- maximum number of entries in a batch before the batch must be transmitted
    }
}


local function schedule_func_exec(batch_processor, delay, batch)
    local hdl, err = timer_at(delay, execute_func, batch_processor, batch)
    if not hdl then
        core.log.error("failed to create process timer: ", err)
        return
    end
end


execute_func = function(premature, batch_processor, batch)
    if premature then
        return
    end

    local ok, err = batch_processor.func(batch.entries)
    if ok then
        ngx_log(DEBUG, fmt("Batch Processor[%s] successfully processed the entries", batch_processor.name))

    else
        batch.retry_count = batch.retry_count + 1
        if batch.retry_count < batch_processor.max_retry_count then
            core.log.warn(fmt("Batch Processor[%s] failed to process entries: ", batch_processor.name), err)
            schedule_func_exec(batch_processor, batch_processor.retry_delay, batch)
        else
            core.log.error(fmt("Batch Processor[%s] exceeded the max_retry_count[%d], dropping the entries", batch_processor.name, batch.retry_count))
        end
    end
end


local function flush_buffer(premature, batch_processor)

    if premature then
        return
    end

    if now() - batch_processor.last_entry_t >= batch_processor.inactive_timeout or
            now() - batch_processor.first_entry_t >= batch_processor.buffer_duration then
        ngx_log(DEBUG, fmt("BatchProcessor[%s] buffer duration exceeded, activating buffer flush", batch_processor.name))
        batch_processor:process_buffer()
        batch_processor.isTimerRunning = false
        return
    end

    -- buffer duration did not exceed or the buffer is active, extending the timer
    ngx_log(DEBUG, fmt("BatchProcessor[%s] extending buffer timer", batch_processor.name))
    create_buffer_timer(batch_processor)
end


create_buffer_timer = function(batch_processor)
    local hdl, err = timer_at(batch_processor.inactive_timeout, flush_buffer, batch_processor)
    if not hdl then
        core.log.error("failed to create buffer timer: ", err)
        return
    end
    batch_processor.isTimerRunning = true
end


function Batch_Processor:new(func, config)
    local ok, err = core.schema.check(schema, config)

    if not ok then
        return err
    end

    if not(type(func) == "function") then
        return nil, "Invalid argument, arg #1 must be a function"
    end

    local batch_processor = {
        func = func,
        buffer_duration = config.buffer_duration,
        inactive_timeout = config.inactive_timeout,
        max_retry_count = config.max_retry_count,
        batch_max_size = config.batch_max_size,
        retry_delay = config.retry_delay,
        name = config.name,
        batch_to_process = {},
        entry_buffer = { entries = {}, retry_count = 0},
        isTimerRunning = false,
        first_entry_t = 0,
        last_entry_t = 0
    }

    return setmetatable(batch_processor, Batch_Processor_mt)
end


function Batch_Processor:push(entry)
    -- if the batch size is one then immediately send for processing
    if self.batch_max_size == 1 then
        local batch = { entries = { entry }, retry_count = 0 }
        schedule_func_exec(self, 0, batch)
    end

    local entries = self.entry_buffer.entries
    table.insert(entries, entry)

    if #entries == 1 then
        self.first_entry_t = now()
    end
    self.last_entry_t = now()

    if self.batch_max_size <= #entries then
        ngx_log(DEBUG, fmt("batch processor[%s] batch max size has exceeded", self.name))
        self:process_buffer()
    elseif not self.isTimerRunning then
        create_buffer_timer(self)
    end

end


function Batch_Processor:process_buffer()
    if #self.entry_buffer.entries > 0 then
        ngx_log(DEBUG, fmt("tranferring buffer entries to processing pipe line, buffercount[%d]", #self.entry_buffer.entries))
        self.batch_to_process[#self.batch_to_process + 1] = self.entry_buffer
        self.entry_buffer = { entries = {}, retry_count = 0 }
    end

    if(#self.batch_to_process > 0) then
        repeat
            local batch = remove(self.batch_to_process, 1)
            schedule_func_exec(self, 0, batch)
        until(#self.batch_to_process == 0)
    end
end


return Batch_Processor
