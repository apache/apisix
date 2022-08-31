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

--- Collection of util functions
--
-- @module core.config_util

local core_tab = require("apisix.core.table")
local log = require("apisix.core.log")
local str_byte = string.byte
local str_char = string.char
local ipairs = ipairs
local setmetatable = setmetatable
local tostring = tostring
local type = type


local _M = {}


local function _iterate_values(self, tab)
    while true do
        self.idx = self.idx + 1
        local v = tab[self.idx]
        if type(v) == "table" then
            return self.idx, v
        end
        if v == nil then
            return nil, nil
        end
        -- skip the tombstone
    end
end


function _M.iterate_values(tab)
    local iter = setmetatable({idx = 0}, {__call = _iterate_values})
    return iter, tab, 0
end


-- Add a clean handler to a runtime configuration item.
-- The clean handler will be called when the item is deleted from configuration
-- or cancelled. Note that Nginx worker exit doesn't trigger the clean handler.
-- Return an index so that we can cancel it later.
function _M.add_clean_handler(item, func)
    if not item.clean_handlers._id then
        item.clean_handlers._id = 1
    end

    local id = item.clean_handlers._id
    item.clean_handlers._id = item.clean_handlers._id + 1
    core_tab.insert(item.clean_handlers, {f = func, id = id})
    return id
end


-- cancel a clean handler added by add_clean_handler.
-- If `fire` is true, call the clean handler.
function _M.cancel_clean_handler(item, idx, fire)
    local pos, f
    -- the number of pending clean handler is small so we can cancel them in O(n)
    for i, clean_handler in ipairs(item.clean_handlers) do
        if clean_handler.id == idx then
            pos = i
            f = clean_handler.f
            break
        end
    end

    if not pos then
        log.error("failed to find clean_handler with idx ", idx)
        return
    end

    core_tab.remove(item.clean_handlers, pos)
    if fire then
        f(item)
    end
end


-- fire all clean handlers added by add_clean_handler.
function _M.fire_all_clean_handlers(item)
    if not item.clean_handlers then
        return
    end

    for _, clean_handler in ipairs(item.clean_handlers) do
        clean_handler.f(item)
    end

    item.clean_handlers = nil
end


---
-- Convert different time units to seconds as time units.
-- Time intervals can be specified in milliseconds, seconds, minutes, hours, days and so on,
-- using the following suffixes:
-- ms	milliseconds
-- s	seconds
-- m	minutes
-- h	hours
-- d	days
-- w	weeks
-- M	months, 30 days
-- y	years, 365 days
-- Multiple units can be combined in a single value by specifying them in the order from the most
-- to the least significant, and optionally separated by whitespace.
-- A value without a suffix means seconds.
--
-- @function core.config_util.parse_time_unit
-- @tparam number|string s Strings with time units, e.g. "60m".
-- @treturn number Number of seconds after conversion
-- @usage
-- local seconds = core.config_util.parse_time_unit("60m") -- 3600
function _M.parse_time_unit(s)
    local typ = type(s)
    if typ == "number" then
        return s
    end

    if typ ~= "string" or #s == 0 then
        return nil, "invalid data: " .. tostring(s)
    end

    local size = 0
    local size_in_unit = 0
    local step = 60 * 60 * 24 * 365
    local with_ms = false
    for i = 1, #s do
        local scale
        local unit = str_byte(s, i)
        if unit == 121 then -- y
            scale = 60 * 60 * 24 * 365
        elseif unit == 77 then -- M
            scale = 60 * 60 * 24 * 30
        elseif unit == 119 then -- w
            scale = 60 * 60 * 24 * 7
        elseif unit == 100 then -- d
            scale = 60 * 60 * 24
        elseif unit == 104 then -- h
            scale = 60 * 60
        elseif unit == 109 then -- m
            unit = str_byte(s, i + 1)
            if unit == 115 then -- ms
                size = size * 1000
                with_ms = true
                step = 0
                break
            end

            scale = 60

        elseif unit == 115 then -- s
            scale = 1
        elseif 48 <= unit and unit <= 57 then
            size_in_unit = size_in_unit * 10 + unit - 48
        elseif unit ~= 32 then
            return nil, "invalid data: " .. str_char(unit)
        end

        if scale ~= nil then
            if scale > step then
                return nil, "unexpected unit: " .. str_char(unit)
            end

            step = scale
            size = size + scale * size_in_unit
            size_in_unit = 0
        end
    end

    if size_in_unit > 0 then
        if step == 1 then
            return nil, "specific unit conflicts with the default unit second"
        end

        size = size + size_in_unit
    end

    if with_ms then
        size = size / 1000
    end

    return size
end


return _M
