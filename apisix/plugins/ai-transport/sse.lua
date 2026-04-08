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

--- SSE (Server-Sent Events) codec and buffer management.

local core = require("apisix.core")
local table = require("apisix.core.table")
local ngx_re = require("ngx.re")
local tonumber = tonumber
local tostring = tostring
local ipairs = ipairs

local _M = {}


--- Decode an SSE text chunk into a list of event tables.
-- Each event has: type (string), data (string), id (string|nil), retry (number|nil).
function _M.decode(chunk)
    local events = {}

    if not chunk then
        return events
    end

    local raw_events, err = ngx_re.split(chunk, "\\r?\\n\\r?\\n")
    if not raw_events then
        core.log.warn("failed to split SSE chunk: ", err)
        return events
    end
    for _, raw_event in ipairs(raw_events) do
        local event = {
            type = "message",
            data = {},
            id = nil,
            retry = nil
        }
        local lines, err = ngx_re.split(raw_event, "\\r?\\n")
        if not lines then
            core.log.warn("failed to split event lines: ", err)
            goto CONTINUE
        end

        for _, line in ipairs(lines) do
            local name, value = line:match("^([^:]+): ?(.*)$")
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

        event.data = table.concat(event.data, "\n")

        table.insert(events, event)

        ::CONTINUE::
    end

    return events
end


--- Encode an event table into an SSE text chunk.
function _M.encode(event)
    local parts = {}

    if event.type and event.type ~= "message" then
        table.insert(parts, "event: " .. event.type)
    end

    if event.id then
        table.insert(parts, "id: " .. event.id)
    end

    if event.retry then
        table.insert(parts, "retry: " .. tostring(event.retry))
    end

    if event.data then
        for line in (event.data .. "\n"):gmatch("(.-)\n") do
            table.insert(parts, "data: " .. line)
        end
    end

    return table.concat(parts, "\n") .. "\n\n"
end


--- Split an SSE buffer at the last complete event boundary.
-- Returns (complete_events, remainder) where complete_events includes
-- all data up to and including the last "\n\n" or "\r\n\r\n" boundary,
-- and remainder holds any trailing incomplete event data.
-- Returns ("", buf) when no boundary is found.
function _M.split_buf(buf)
    local last_end
    local search_pos = 1
    while true do
        local pos_lf   = buf:find("\n\n",     search_pos, true)
        local pos_crlf = buf:find("\r\n\r\n", search_pos, true)

        local pos, boundary_len
        if pos_lf and pos_crlf then
            if pos_lf <= pos_crlf then
                pos, boundary_len = pos_lf, 2
            else
                pos, boundary_len = pos_crlf, 4
            end
        elseif pos_lf then
            pos, boundary_len = pos_lf, 2
        elseif pos_crlf then
            pos, boundary_len = pos_crlf, 4
        else
            break
        end

        last_end = pos + boundary_len - 1
        search_pos = pos + boundary_len
    end
    if not last_end then
        return "", buf
    end
    return buf:sub(1, last_end), buf:sub(last_end + 1)
end


return _M
