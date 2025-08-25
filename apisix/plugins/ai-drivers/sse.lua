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
local ipairs = ipairs
local _M = {}

local ngx_re = require("ngx.re")

function _M.decode(chunk)
    local events = {}

    if not chunk then
        return events
    end

    -- Split chunk into individual SSE events
    local raw_events, err = ngx_re.split(chunk, "\n\n")
    if not raw_events then
        core.log.warn("failed to split SSE chunk: ", err)
        return events
    end
    for _, raw_event in ipairs(raw_events) do
        local event = {
            type = "message",  -- default event type
            data = {},
            id = nil,
            retry = nil
        }
        if core.string.find(raw_event, "data: [DONE]") then
            event.type = "done"
            event.data = "[DONE]\n\n"
            table.insert(events, event)
            goto CONTINUE
        end
        local lines, err = ngx_re.split(raw_event, "\n")
        if not lines then
            core.log.warn("failed to split event lines: ", err)
            goto CONTINUE
        end

        for _, line in ipairs(lines) do
            local name, value = line:match("^([^:]+): ?(.+)$")
            if not name then goto NEXT_LINE end

            name = name:lower()

            if name == "event" then
                event.type = value
            elseif name == "data" then
                table.insert(event.data, value)
            elseif name == "id" then
                event.id = value
            elseif name == "retry" then
                event.retry = tonumber(value)
            end

            ::NEXT_LINE::
        end

        -- Join data lines with newline
        event.data = table.concat(event.data, "\n")
        table.insert(events, event)

        ::CONTINUE::
    end

    return events
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
