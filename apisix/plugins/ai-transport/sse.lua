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

local table = require("apisix.core.table")
local tonumber = tonumber
local tostring = tostring

local _M = {
    -- Cap on bytes that decode_buf (and split_buf) may leave in `remainder`.
    -- Read by the streaming loop in ai-providers/base.lua to bound the buffer
    -- when frames don't complete. SSE frames are small (text events delimited
    -- by blank lines), so 1 MiB is plenty.
    max_remainder = 1024 * 1024,
}


-- Parse one raw SSE event block (text between two boundary markers) into
-- an event table.  Returns nil for empty / comment-only blocks.
local function parse_raw_event(raw)
    local event = {
        type  = "message",
        data  = {},
        id    = nil,
        retry = nil,
    }
    local has_field = false

    local pos = 1
    local raw_len = #raw
    while pos <= raw_len do
        local nl = raw:find("\n", pos, true)
        local line
        if nl then
            line = raw:sub(pos, nl - 1)
            pos  = nl + 1
        else
            line = raw:sub(pos)
            pos  = raw_len + 1
        end

        -- Strip trailing \r for CRLF line endings.
        if line:sub(-1) == "\r" then
            line = line:sub(1, -2)
        end

        if #line == 0 then
            -- blank line inside a raw block (shouldn't happen after split, skip)
            goto NEXT_LINE
        end

        -- Find the field:value separator.  Plain search avoids pattern engine.
        local colon = line:find(":", 1, true)
        if not colon then goto NEXT_LINE end
        -- Lines starting with ":" are SSE comments; skip without setting has_field.
        if colon == 1 then goto NEXT_LINE end

        local name  = line:sub(1, colon - 1):lower()
        local value = line:sub(colon + 1)
        -- Strip a single leading space per the SSE spec.
        if value:sub(1, 1) == " " then
            value = value:sub(2)
        end

        has_field = true
        if name == "data" then
            table.insert(event.data, value)
        elseif name == "event" then
            event.type = value
        elseif name == "id" then
            event.id = value
        elseif name == "retry" then
            event.retry = tonumber(value)
        end

        ::NEXT_LINE::
    end

    if not has_field then
        return nil
    end
    event.data = table.concat(event.data, "\n")
    return event
end


-- Find the next event boundary (\n\n or \r\n\r\n) starting at `pos`.
-- Returns (ev_end, next_pos) or (nil, nil) when none found.
-- ev_end   = last byte of the event content (before the boundary)
-- next_pos = first byte after the boundary
local function next_boundary(buf, pos)
    local p_lf   = buf:find("\n\n",     pos, true)
    local p_crlf = buf:find("\r\n\r\n", pos, true)

    if p_lf and p_crlf then
        if p_lf <= p_crlf then
            return p_lf - 1, p_lf + 2
        else
            return p_crlf - 1, p_crlf + 4
        end
    elseif p_lf then
        return p_lf - 1, p_lf + 2
    elseif p_crlf then
        return p_crlf - 1, p_crlf + 4
    end
    return nil, nil
end


--- Decode an SSE text chunk into a list of event tables.
-- Each event has: type (string), data (string), id (string|nil), retry (number|nil).
-- The chunk is expected to contain only complete events (no trailing partial event).
-- Replaces the former ngx_re.split-based implementation; no PCRE overhead.
function _M.decode(chunk)
    local events = {}
    if not chunk or chunk == "" then
        return events
    end

    local pos = 1
    local len = #chunk
    while pos <= len do
        local ev_end, next_pos = next_boundary(chunk, pos)
        if not ev_end then
            -- No trailing blank line: treat the remaining content as a complete
            -- event for backward compatibility with callers that pass full response
            -- bodies or per-chunk bodies without a terminal blank line.
            local event = parse_raw_event(chunk:sub(pos))
            if event then
                table.insert(events, event)
            end
            break
        end
        local raw = chunk:sub(pos, ev_end)
        local event = parse_raw_event(raw)
        if event then
            table.insert(events, event)
        end
        pos = next_pos
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


--- Decode a raw SSE buffer in one forward pass, returning (events, remainder).
-- Combines the split_buf + decode two-step into a single scan for use in
-- high-throughput loops (e.g. ai-providers/base.lua).
-- `remainder` holds any trailing bytes that did not end with a boundary marker.
function _M.decode_buf(buf)
    local events = {}
    local pos = 1
    local len = #buf
    local last_complete_pos = 1

    while pos <= len do
        local ev_end, next_pos = next_boundary(buf, pos)
        if not ev_end then
            break
        end
        local raw = buf:sub(pos, ev_end)
        local event = parse_raw_event(raw)
        if event then
            table.insert(events, event)
        end
        last_complete_pos = next_pos
        pos = next_pos
    end

    local remainder = (last_complete_pos <= len) and buf:sub(last_complete_pos) or ""
    return events, remainder
end


-- Returns (complete_data, remainder) where complete_data includes
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
