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

--- AWS EventStream binary framing codec.
-- Used by Bedrock ConverseStream, Kinesis SubscribeToShard, S3 SelectObjectContent,
-- and Transcribe streaming. Each frame:
--
--   prelude (12 bytes)
--     total_length    BE uint32  -- entire frame including trailing CRC
--     headers_length  BE uint32  -- size of the headers section
--     prelude_crc     BE uint32  -- CRC32 of the first 8 bytes
--   headers (headers_length bytes)
--     repeated entries: name_len(u8) name(bytes) value_type(u8) value...
--   payload (total_length - 16 - headers_length bytes)
--   message_crc (4 bytes BE uint32)  -- CRC32 of bytes [0, total_length-4)
--
-- This module provides the same API surface as ai-transport.sse so the base
-- provider can pick a framing module by name.

local core = require("apisix.core")
local ngx = ngx
local ngx_crc32 = ngx.crc32_long
local string_byte = string.byte
local string_sub = string.sub
local tostring = tostring

-- Hard cap on a single frame size to avoid memory blowups on malformed input.
-- AWS documents ConverseStream frames as well under 1 MiB; pick 16 MiB to be
-- safe for other services that use this codec.
local MAX_FRAME_SIZE = 16 * 1024 * 1024

-- Header value type tags (AWS EventStream spec). Bedrock only sends type 7
-- (string), but we decode 6/7 for robustness against other AWS services.
local TYPE_TRUE       = 0
local TYPE_FALSE      = 1
local TYPE_BYTE       = 2
local TYPE_SHORT      = 3
local TYPE_INTEGER    = 4
local TYPE_LONG       = 5
local TYPE_BYTE_ARRAY = 6
local TYPE_STRING     = 7
local TYPE_TIMESTAMP  = 8
local TYPE_UUID       = 9

local _M = {
    -- Cap on bytes split_buf may leave in `remainder`. The streaming loop
    -- in ai-providers.base uses this to bound the buffer when a frame has
    -- not yet completed. A single in-progress frame can be up to
    -- MAX_FRAME_SIZE bytes, so the remainder cap matches that.
    max_remainder = MAX_FRAME_SIZE,
}


local function read_u32_be(s, pos)
    local b1, b2, b3, b4 = string_byte(s, pos, pos + 3)
    if not b4 then
        return nil
    end
    return b1 * 16777216 + b2 * 65536 + b3 * 256 + b4
end


local function read_u16_be(s, pos)
    local b1, b2 = string_byte(s, pos, pos + 1)
    if not b2 then
        return nil
    end
    return b1 * 256 + b2
end


-- Decode a single frame's headers section.
-- @param s string  Full frame buffer
-- @param start int  1-based start of headers
-- @param stop int   1-based end of headers (inclusive)
-- @return table|nil  Map of header name -> string value
-- @return string|nil error
local function parse_headers(s, start, stop)
    local headers = {}
    local pos = start
    while pos <= stop do
        local name_len = string_byte(s, pos)
        if not name_len then
            return nil, "truncated header entry"
        end
        pos = pos + 1
        if pos + name_len - 1 > stop then
            return nil, "header name extends past headers section"
        end
        local name = string_sub(s, pos, pos + name_len - 1)
        pos = pos + name_len

        local value_type = string_byte(s, pos)
        if not value_type then
            return nil, "missing header value type"
        end
        pos = pos + 1

        if value_type == TYPE_STRING or value_type == TYPE_BYTE_ARRAY then
            local val_len = read_u16_be(s, pos)
            if not val_len then
                return nil, "truncated header value length"
            end
            pos = pos + 2
            if pos + val_len - 1 > stop then
                return nil, "header value extends past headers section"
            end
            headers[name] = string_sub(s, pos, pos + val_len - 1)
            pos = pos + val_len
        elseif value_type == TYPE_TRUE then
            headers[name] = true
        elseif value_type == TYPE_FALSE then
            headers[name] = false
        elseif value_type == TYPE_BYTE then
            if pos > stop then
                return nil, "truncated header byte value"
            end
            headers[name] = string_byte(s, pos)
            pos = pos + 1
        elseif value_type == TYPE_SHORT then
            if pos + 1 > stop then
                return nil, "truncated header short value"
            end
            headers[name] = read_u16_be(s, pos)
            pos = pos + 2
        elseif value_type == TYPE_INTEGER then
            if pos + 3 > stop then
                return nil, "truncated header integer value"
            end
            headers[name] = read_u32_be(s, pos)
            pos = pos + 4
        elseif value_type == TYPE_LONG then
            if pos + 7 > stop then
                return nil, "truncated header long value"
            end
            -- 64-bit ints don't fit in a Lua double; keep raw bytes.
            headers[name] = string_sub(s, pos, pos + 7)
            pos = pos + 8
        elseif value_type == TYPE_TIMESTAMP then
            if pos + 7 > stop then
                return nil, "truncated header timestamp value"
            end
            headers[name] = string_sub(s, pos, pos + 7)
            pos = pos + 8
        elseif value_type == TYPE_UUID then
            if pos + 15 > stop then
                return nil, "truncated header uuid value"
            end
            headers[name] = string_sub(s, pos, pos + 15)
            pos = pos + 16
        else
            return nil, "unknown header value type: " .. value_type
        end
    end
    return headers
end


--- Split a buffer at the last complete frame boundary.
-- A "complete" frame here is one whose prelude length fields are sane,
-- whose full byte range is present, AND whose prelude CRC validates.
-- The CRC check matters because split_buf advances pos based on
-- total_length alone — without it, a frame with a sane length but bad
-- prelude CRC would be consumed into `complete`, decode() would stop on
-- it, and any valid frames behind it in the same chunk would be lost
-- (already past pos, not preserved in remainder). Validating here keeps
-- corrupt frames in `remainder` so the caller can either resync or trip
-- max_remainder. Message CRC is intentionally not checked here (decode()
-- handles that); a frame with a good prelude but bad payload CRC is rare
-- and any frames behind it in the same chunk would still be advanced
-- past — accepted trade-off vs. the cost of computing the message CRC
-- twice on every frame.
-- @param buf string
-- @return string complete   Concatenated complete frames (or "" if none).
-- @return string remainder  Bytes after the last complete frame.
function _M.split_buf(buf)
    local len = #buf
    local pos = 1
    while pos + 11 <= len do
        local total_length = read_u32_be(buf, pos)
        if not total_length or total_length < 16 or total_length > MAX_FRAME_SIZE then
            -- Corrupt total_length field. Stop and leave the bytes in the
            -- remainder; decode() never sees them.
            break
        end
        if pos + total_length - 1 > len then
            -- Frame not yet fully in buffer — wait for more chunks.
            break
        end
        local prelude_crc = read_u32_be(buf, pos + 8)
        if ngx_crc32(string_sub(buf, pos, pos + 7)) ~= prelude_crc then
            -- Prelude CRC mismatch. Don't advance: keep this corrupt
            -- frame and everything after in `remainder`, so we don't
            -- silently consume valid frames sitting behind it.
            break
        end
        pos = pos + total_length
    end
    if pos == 1 then
        return "", buf
    end
    return string_sub(buf, 1, pos - 1), string_sub(buf, pos)
end


--- Decode a buffer of complete frames into events.
-- @param buf string  Buffer containing zero or more complete frames.
-- @return table  Array of {headers = {string -> string}, payload = string}.
function _M.decode(buf)
    local events = {}
    local len = #buf
    local pos = 1
    while pos <= len do
        if pos + 11 > len then
            core.log.warn("eventstream: truncated prelude at offset ", pos - 1,
                          " (buffer ", len, " bytes)")
            return events
        end
        local total_length = read_u32_be(buf, pos)
        local headers_length = read_u32_be(buf, pos + 4)
        local prelude_crc = read_u32_be(buf, pos + 8)

        if not total_length or total_length < 16 or total_length > MAX_FRAME_SIZE then
            core.log.warn("eventstream: invalid total_length ",
                          tostring(total_length), " at offset ", pos - 1)
            return events
        end
        if headers_length > total_length - 16 then
            core.log.warn("eventstream: headers_length ", headers_length,
                          " exceeds frame body")
            return events
        end
        if pos + total_length - 1 > len then
            core.log.warn("eventstream: incomplete frame at offset ", pos - 1)
            return events
        end

        local computed_prelude_crc = ngx_crc32(string_sub(buf, pos, pos + 7))
        if computed_prelude_crc ~= prelude_crc then
            core.log.warn("eventstream: prelude CRC mismatch at offset ", pos - 1,
                          " expected ", prelude_crc, " got ", computed_prelude_crc)
            return events
        end

        local headers_start = pos + 12
        local payload_start = headers_start + headers_length
        local payload_end = pos + total_length - 5  -- inclusive
        local message_crc = read_u32_be(buf, payload_end + 1)

        local computed_message_crc = ngx_crc32(string_sub(buf, pos, payload_end))
        if computed_message_crc ~= message_crc then
            core.log.warn("eventstream: message CRC mismatch at offset ", pos - 1,
                          " expected ", message_crc, " got ", computed_message_crc)
            return events
        end

        local headers, herr
        if headers_length > 0 then
            headers, herr = parse_headers(buf, headers_start, payload_start - 1)
            if not headers then
                core.log.warn("eventstream: failed to parse headers: ", herr)
                return events
            end
        else
            headers = {}
        end

        events[#events + 1] = {
            headers = headers,
            payload = string_sub(buf, payload_start, payload_end),
        }
        pos = pos + total_length
    end
    return events
end


return _M
