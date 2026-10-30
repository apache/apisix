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
    local uses = {}
    local ok = walk(conf, {}, {}, function(value, allowed, parent, key)
        if type(value) ~= "string" then
            return
        end
        for marker in value:gmatch(prefix .. "%d+__") do
            if records[marker] then
                local use = uses[marker] or {targets = {}}
                uses[marker] = use
                use.ssl = use.ssl or allowed
                if allowed and value == marker and origins[marker] then
                    local targets = use.targets
                    targets[#targets + 1] = {parent = parent, key = key}
                else
                    use.unsafe = true
                end
            end
        end
    end)
    -- A shared anchor must not change a non-SSL consumer's substitution behavior.
    local fields, unprotected = {}, false
    for marker, use in pairs(uses) do
        if ok and not use.unsafe then
            fields[marker] = use.targets
        elseif use.ssl then
            unprotected = true
        end
    end
    return {config = conf, fields = fields, unprotected = unprotected}
end


-- Save original values and prepare a repeatable substitution with optional markers.
local function prepare_substitution(text, substitute)
    local values, multiline = {}, false
    local expanded, _, err = substitute(text, function(value)
        values[#values + 1] = {value = value}
        multiline = multiline or value:find("[\r\n]") ~= nil
        return value
    end)
    if err then
        return nil, err
    end
    local env = {expanded = expanded}
    if not multiline then
        return env
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
    env.render = function(selected)
        local index = 0
        return substitute(text, function()
            index = index + 1
            local record = values[index]
            return selected[record.marker] and record.marker or record.value
        end)
    end
    env.records, env.prefix = records, prefix
    return env
end


-- Discover supported fields, then recheck after expanding all other variables.
-- Return nil to use legacy YAML; the second result requests a warning.
local function restore_ssl(env)
    local ok, discovered = pcall(inspect_fields, env.render(env.records), env.records, env.prefix)
    if not ok then
        return nil
    end
    local selected = discovered.fields
    if not next(selected) then
        return nil, discovered.unprotected
    end
    local parsed, final = pcall(inspect_fields, env.render(selected), env.records, env.prefix)
    if not parsed then
        return nil, true
    end
    -- Other substitutions can move or synthesize markers. Check every selected
    -- occurrence before restoring any value; never scan the restored PEM again.
    for marker in pairs(selected) do
        if not final.fields[marker] then
            return nil, true
        end
    end
    for marker in pairs(selected) do
        for _, target in ipairs(final.fields[marker]) do
            target.parent[target.key] = env.records[marker].value
        end
    end
    return final.config, discovered.unprotected
end


function _M.load(text, substitute, warn)
    local env, err = prepare_substitution(text, substitute)
    if not env then
        return nil, err
    end
    local conf, unprotected
    if env.records then
        conf, unprotected = restore_ssl(env)
    end
    if unprotected and warn then
        warn("cannot preserve some multiline SSL environment values; "
             .. "using legacy YAML substitution for them (consider $ENV:// references)")
    end
    return conf or yaml.load(env.expanded)
end


return _M
