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

local yaml = require("lyaml")
local parser = require("yaml").parser
local pairs = pairs
local next = next
local ipairs = ipairs
local type = type
local pcall = pcall
local _M = {}


local function is_ssl_field(path)
    if path[1] ~= "ssls" or type(path[2]) ~= "number" then
        return false
    end
    if #path == 3 then
        return path[3] == "cert" or path[3] == "key"
    end
    if #path == 4 then
        return ((path[3] == "certs" or path[3] == "keys") and type(path[4]) == "number")
               or (path[3] == "client" and path[4] == "ca")
    end
    return false
end


-- Visit aliases once per path, but abort discovery on cycles or excessive depth.
-- The caller then uses the existing YAML load, without introducing a new error.
local function walk(value, path, active, visit, parent, key)
    if type(value) ~= "table" then
        visit(value, is_ssl_field(path), parent, key)
        return true
    end
    if active[value] or #path > 128 then
        return false
    end
    active[value] = true
    for k, v in pairs(value) do
        visit(k, false)
        path[#path + 1] = k
        if not walk(v, path, active, visit, value, k) then
            return false
        end
        path[#path] = nil
    end
    active[value] = nil
    return true
end


-- A decoded scalar may spell a marker using YAML escapes. Only accept markers
-- that occur literally in that scalar's source span, not user-authored lookalikes.
local function scalar_origins(text, records)
    local offsets, index = {}, 0
    for byte = 1, #text do
        local b = text:byte(byte)
        if b < 128 or b >= 192 then
            offsets[index] = byte
            index = index + 1
        end
    end
    offsets[index] = #text + 1
    local origins, ambiguous = {}, {}
    for event in parser(text) do
        if event.type == "SCALAR" and records[event.value] then
            local first = offsets[event.start_mark.index]
            local last = offsets[event.end_mark.index]
            local source = first and last and text:sub(first, last - 1)
            if source and source:find(event.value, 1, true)
               and (event.style == "PLAIN" or event.style == "SINGLE_QUOTED"
                    or event.style == "DOUBLE_QUOTED") then
                origins[event.value] = true
            else
                ambiguous[event.value] = true
            end
        end
        if event.type == "STREAM_END" then
            break
        end
    end
    for marker in pairs(ambiguous) do
        origins[marker] = nil
    end
    return origins
end


-- Use the same path and provenance checks for discovery and final restoration.
local function inspect_fields(text, records, prefix)
    local conf = yaml.load(text)
    local origins = scalar_origins(text, records)
    local fields, outside, ssl = {}, {}, {}
    local ok = walk(conf, {}, {}, function(value, allowed, parent, key)
        if type(value) ~= "string" then
            return
        end
        for marker in value:gmatch(prefix .. "%d+__") do
            if records[marker] then
                if allowed then
                    ssl[marker] = true
                end
                if allowed and value == marker and origins[marker] then
                    fields[marker] = fields[marker] or {}
                    local targets = fields[marker]
                    targets[#targets + 1] = {parent, key, records[marker].value}
                else
                    outside[marker] = true
                end
            end
        end
    end)
    if not ok then
        return nil, nil, next(ssl) ~= nil
    end
    -- A shared anchor must not change a non-SSL consumer's substitution behavior.
    for marker in pairs(outside) do
        fields[marker] = nil
    end
    for marker in pairs(ssl) do
        if not fields[marker] then
            return conf, fields, true
        end
    end
    return conf, fields
end


function _M.load(text, substitute, warn)
    local values, multiline = {}, false
    local expanded, _, err = substitute(text, function(value)
        values[#values + 1] = {value = value}
        multiline = multiline or value:find("[\r\n]") ~= nil
        return value
    end)
    if err then
        return nil, err
    end
    if not multiline then
        return yaml.load(expanded)
    end

    local serial, prefix = 0
    local collision
    repeat
        serial = serial + 1
        prefix = "__APISIX_SSL_ENV_" .. serial .. "_"
        collision = text:find(prefix, 1, true)
        for _, record in ipairs(values) do
            collision = collision or record.value:find(prefix, 1, true)
        end
    until not collision

    local records = {}
    for i, record in ipairs(values) do
        if record.value:find("[\r\n]") then
            record.marker = prefix .. i .. "__"
            records[record.marker] = record
        end
    end
    -- Replaying substitution over the same source visits occurrences in the same order.
    local function render(selected)
        local index = 0
        return substitute(text, function()
            index = index + 1
            local record = values[index]
            return selected[record.marker] and record.marker or record.value
        end)
    end
    local function warn_fallback()
        if warn then
            warn("cannot preserve some multiline SSL environment values; "
                 .. "using legacy YAML substitution for them (consider $ENV:// references)")
            warn = nil
        end
    end
    local ok, _, selected, unprotected = pcall(inspect_fields, render(records), records, prefix)
    if unprotected then
        warn_fallback()
    end
    if not ok or not selected or not next(selected) then
        return yaml.load(expanded)
    end

    local parsed, conf, fields = pcall(inspect_fields, render(selected), records, prefix)
    if not parsed or not fields then
        warn_fallback()
        return yaml.load(expanded)
    end
    -- Other substitutions can move or synthesize markers. Check every selected
    -- occurrence before restoring any value; never scan the restored PEM again.
    for marker in pairs(selected) do
        if not fields[marker] then
            warn_fallback()
            return yaml.load(expanded)
        end
    end
    for marker in pairs(selected) do
        for _, target in ipairs(fields[marker]) do
            target[1][target[2]] = target[3]
        end
    end
    return conf
end


return _M
