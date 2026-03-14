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
local table = require("apisix.core.table")
local tonumber = tonumber
local tostring = tostring
local string = string
local string_sub = string.sub
local _M = {}


-- Character code constants for SSE parsing
local CHAR_NEWLINE = string.byte("\n")
local CHAR_COLON = string.byte(":")
local CHAR_SPACE = string.byte(" ")

-- Check if the event is a termination event (contains [DONE])
-- @param event: The event object to check
-- @return boolean: True if event is done, false otherwise
local function is_event_done(event)
    if event and event.raw_event then
        return core.string.find(event.raw_event, "data: [DONE]")
    end
    return false
end

-- Parse event value from body string
-- @param body: The body string containing the event
-- @param start_idx: Start index of the value
-- @param end_idx: End index of the value
-- @return string: The parsed value or empty string if indices are invalid
local function parse_event_value(body, start_idx, end_idx)
    if not start_idx or not end_idx then
        return ""
    end
    return string_sub(body, start_idx, end_idx)
end

-- Decode SSE chunk into events
-- @param chunk: The incoming chunk of data
-- @param buffer: The buffer from previous chunks (may be nil)
-- @return table: Array of parsed events
-- @return string|nil: New buffer for next chunk (may be nil)
function _M.decode(chunk, buffer)
    local events = {}

    if not chunk then
        return events, buffer
    end

    -- Combine buffer with current chunk if buffer exists
    local body = chunk
    if buffer and #buffer > 0 then
        body = buffer .. chunk
    end

    -- Track parsing state
    local event_start_index = nil
    local line_start_index = nil
    local value_start_index = nil
    local current_key = ""
    local current_event = {
        type = "message",
        data = {},
        id = nil,
        retry = nil
    }

    -- Parse the body character by character
    local i = 1
    local length = #body
    while i <= length do
        local ch = string.byte(body, i)

        if ch ~= CHAR_NEWLINE then
            if not line_start_index then
                if not event_start_index then
                    event_start_index = i
                end
                line_start_index = i
                value_start_index = nil
            end
            if not value_start_index then
                if ch == CHAR_COLON then
                    value_start_index = i + 1
                    current_key = string_sub(body, line_start_index, i - 1)
                end
            elseif value_start_index == i and ch == CHAR_SPACE then
                value_start_index = i + 1
            end
        else
            if line_start_index then
                if value_start_index then
                    local value = parse_event_value(body, value_start_index, i - 1)
                    if current_key == "event" then
                        current_event.type = value
                    elseif current_key == "data" then
                        table.insert(current_event.data, value)
                    elseif current_key == "id" then
                        current_event.id = value
                    elseif current_key == "retry" then
                        current_event.retry = tonumber(value)
                    end
                end
            else
                current_event.raw_event = string_sub(body, event_start_index or 1, i)
                if is_event_done(current_event) then
                    current_event.type = "done"
                    current_event.data = "[DONE]\n\n"
                else
                    current_event.data = table.concat(current_event.data, "\n")
                end
                table.insert(events, current_event)
                event_start_index = nil
                current_event = {
                    type = "message",
                    data = {},
                    id = nil,
                    retry = nil
                }
            end

            line_start_index = nil
            value_start_index = nil
            current_key = ""
        end

        i = i + 1
    end

    -- Save incomplete event to buffer for next chunk
    local new_buffer = nil
    if event_start_index and event_start_index <= length then
        new_buffer = string_sub(body, event_start_index)
    end

    return events, new_buffer
end

function _M.encode(event)
    local parts = {}

    if event.type and event.type ~= "message" and event.type ~= "done" then
        table.insert(parts, "event: " .. event.type)
    end

    if event.id then
        table.insert(parts, "id: " .. event.id)
    end

    if event.retry then
        table.insert(parts, "retry: " .. tostring(event.retry))
    end

    if event.data then
        if event.type == "done" then
            table.insert(parts, "data: " .. event.data)
        else
            for line in event.data:gmatch("([^\n]+)") do
                table.insert(parts, "data: " .. line)
            end
        end

    end

    table.insert(parts, "")  -- Add empty line to separate events
    return table.concat(parts, "\n")
end

return _M
