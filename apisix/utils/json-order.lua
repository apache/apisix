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

--- JSON key order: read it from the bytes a body arrived as, and keep it when
-- the decoded (and possibly changed) table is encoded again.
--
-- Lua tables do not remember key order, so a JSON body that is decoded,
-- changed and encoded again comes out in hash order (cjson) or sorted
-- (core.json.canonical_encode). For most fields that is harmless, but
-- providers generate structured output in the order of a JSON Schema's
-- properties, so a reordered schema changes the answer.
--
-- shape(raw) records, for every object in the original bytes, its keys in
-- order, and which values were arrays. encode(value, shape) writes value with
-- the keys the original had first, in its order, then any other keys sorted,
-- so the same input always gives the same bytes. An empty table is [] when it
-- carries core.json.array_mt (as core.json.decode gives an empty array) or
-- when the original had an array there, so one built in Lua stays [] too.
-- Values come from the table, never from the raw bytes, so a shape from older
-- bytes only affects order.

local core = require("apisix.core")
local type = type
local pairs = pairs
local ipairs = ipairs
local next = next
local pcall = pcall
local error = error
local tostring = tostring
local tonumber = tonumber
local getmetatable = getmetatable
local byte = string.byte
local char = string.char
local sub = string.sub
local find = string.find
local gsub = string.gsub
local format = string.format
local floor = math.floor
local huge = math.huge
local table_concat = table.concat
local table_sort = table.sort

local MAX_DEPTH = 1000
local MAX_SAFE_INTEGER = 9007199254740992  -- 2^53

local _M = {}

-- Shapes: an object is {keys = {...}, child = {key -> shape or false}}, an
-- array {array = true, items = {index -> shape or false}}; false (or nil)
-- stands for a scalar.

local UNESCAPE = {['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f",
                  n = "\n", r = "\r", t = "\t"}


local function utf8(cp)
    if cp < 0x80 then return char(cp) end
    if cp < 0x800 then return char(0xC0 + floor(cp / 0x40), 0x80 + cp % 0x40) end
    if cp < 0x10000 then
        return char(0xE0 + floor(cp / 0x1000), 0x80 + floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
    end
    return char(0xF0 + floor(cp / 0x40000), 0x80 + floor(cp / 0x1000) % 0x40,
                0x80 + floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
end


-- A key's text between its quotes, unescaped.
local function unescape(s)
    if not find(s, "\\", 1, true) then return s end
    local out, i = {}, 1
    while true do
        local j = find(s, "\\", i, true)
        if not j then
            out[#out + 1] = sub(s, i)
            return table_concat(out)
        end
        out[#out + 1] = sub(s, i, j - 1)
        local c = sub(s, j + 1, j + 1)
        if c == "u" then
            local cp = tonumber(sub(s, j + 2, j + 5), 16) or 0xFFFD
            i = j + 6
            if cp >= 0xD800 and cp <= 0xDBFF and sub(s, i, i + 1) == "\\u" then
                local low = tonumber(sub(s, i + 2, i + 5), 16)
                if low and low >= 0xDC00 and low <= 0xDFFF then
                    cp = 0x10000 + (cp - 0xD800) * 0x400 + (low - 0xDC00)
                    i = i + 6
                end
            end
            out[#out + 1] = utf8(cp)
        else
            out[#out + 1] = UNESCAPE[c] or c
            i = j + 2
        end
    end
end


-- The index of the next non-whitespace byte at or after i (nil at the end).
local function skip(s, i)
    return find(s, "[^ \t\r\n]", i)
end


-- s[i] is a quote: the index just past the closing quote, and the text inside.
local function string_end(s, i)
    local j = i + 1
    while true do
        local k = find(s, '["\\]', j)
        if not k then error("unterminated string") end
        if byte(s, k) == 34 then return k + 1, sub(s, i + 1, k - 1) end
        j = k + 2
    end
end


local parse

local function parse_object(s, i, depth)
    local keys, child = {}, {}
    i = skip(s, i + 1)
    if byte(s, i) == 125 then return {keys = keys, child = child}, i + 1 end
    while true do
        if byte(s, i) ~= 34 then error("expected a key at " .. tostring(i)) end
        local key
        i, key = string_end(s, i)
        key = unescape(key)
        i = skip(s, i)
        if byte(s, i) ~= 58 then error("expected ':' at " .. tostring(i)) end
        local value
        value, i = parse(s, i + 1, depth)
        -- A repeated key keeps its first position and, like cjson, its last value.
        if child[key] == nil then keys[#keys + 1] = key end
        child[key] = value or false
        i = skip(s, i)
        local c = byte(s, i)
        if c == 125 then return {keys = keys, child = child}, i + 1 end
        if c ~= 44 then error("expected ',' or '}' at " .. tostring(i)) end
        i = skip(s, i + 1)
    end
end


local function parse_array(s, i, depth)
    local items = {}
    i = skip(s, i + 1)
    if byte(s, i) == 93 then return {array = true, items = items}, i + 1 end
    while true do
        local value
        value, i = parse(s, i, depth)
        items[#items + 1] = value or false
        i = skip(s, i)
        local c = byte(s, i)
        if c == 93 then return {array = true, items = items}, i + 1 end
        if c ~= 44 then error("expected ',' or ']' at " .. tostring(i)) end
        i = i + 1
    end
end


-- The shape of the JSON value at i (nil for a scalar), and the index after it;
-- depth counts the objects and arrays it sits in (at most MAX_DEPTH, as cjson).
parse = function(s, i, depth)
    i = skip(s, i)
    if not i then error("unexpected end") end
    local c = byte(s, i)
    if c == 123 or c == 91 then
        if depth >= MAX_DEPTH then error("nested too deeply") end
        if c == 123 then return parse_object(s, i, depth + 1) end
        return parse_array(s, i, depth + 1)
    end
    if c == 34 then
        local j = string_end(s, i)
        return nil, j
    end
    -- A number or literal ends at the next delimiter (or the end).
    local j = find(s, "[,%]}%s]", i)
    if j == i then error("unexpected '" .. sub(s, i, i) .. "' at " .. tostring(i)) end
    return nil, j or #s + 1
end


--- The shape of a JSON text: every object's keys in order, and which values
-- are arrays. Returns nil for anything that is not one valid JSON object or
-- array (and for a scalar, which has no keys to order).
function _M.shape(raw)
    if type(raw) ~= "string" then return nil end
    local ok, shape, i = pcall(parse, raw, 1, 0)
    if not ok or not shape or skip(raw, i) then return nil end
    return shape
end


--- The shape at a path of object keys and array indexes, or nil.
function _M.child(shape, ...)
    for _, step in ipairs({...}) do
        if not shape then return nil end
        if type(step) == "number" then
            shape = shape.items and shape.items[step]
        else
            shape = shape.child and shape.child[step]
        end
    end
    return shape or nil
end


local ESCAPE = {['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f",
                ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t"}
for b = 0, 31 do
    local c = char(b)
    ESCAPE[c] = ESCAPE[c] or format("\\u%04x", b)
end
ESCAPE[char(127)] = "\\u007f"


local function encode_string(s)
    return '"' .. gsub(s, '[%c"\\]', ESCAPE) .. '"'
end


local function encode_number(n)
    if n ~= n or n == huge or n == -huge then error("cannot encode " .. tostring(n)) end
    if n == floor(n) and n >= -MAX_SAFE_INTEGER and n <= MAX_SAFE_INTEGER then
        return format("%d", n)
    end
    local s = format("%.14g", n)
    if tonumber(s) ~= n then s = format("%.17g", n) end
    return s
end


-- n when t's keys are exactly 1..n, else nil (t is not empty).
local function sequence_length(t)
    local n = 0
    for k in pairs(t) do
        if type(k) ~= "number" then return nil end
        n = n + 1
    end
    for i = 1, n do
        if t[i] == nil then return nil end
    end
    return n
end


local encode_value

local function encode_object(v, shape, opts, depth)
    local out, done = {}, {}
    local child = shape and shape.child
    for _, k in ipairs(shape and shape.keys or {}) do
        local x = v[k]
        if x ~= nil then
            out[#out + 1] = encode_string(k) .. ":" .. encode_value(x, child[k], opts, depth)
            done[k] = true
        end
    end
    local rest = {}
    for k in pairs(v) do
        if not done[k] then
            if type(k) ~= "string" then error("cannot encode a table with mixed keys") end
            rest[#rest + 1] = k
        end
    end
    table_sort(rest)
    for _, k in ipairs(rest) do
        out[#out + 1] = encode_string(k) .. ":"
                        .. encode_value(v[k], child and child[k], opts, depth)
    end
    return "{" .. table_concat(out, ",") .. "}"
end


encode_value = function(v, shape, opts, depth)
    local t = type(v)
    if t == "string" then return encode_string(v) end
    if t == "number" then return encode_number(v) end
    if t == "boolean" then return v and "true" or "false" end
    -- cjson.null / ngx.null are light userdata; tests may use a table sentinel.
    if t == "userdata" or (opts.null ~= nil and v == opts.null) then return "null" end
    if t ~= "table" then error("cannot encode a " .. t) end
    if depth >= MAX_DEPTH then error("nested too deeply") end
    depth = depth + 1
    if opts.shapes then
        local own = opts.shapes[v]
        if own ~= nil then shape = own end
    end
    shape = shape or nil
    if next(v) == nil then
        if (shape and shape.array)
                or (opts.array_mt ~= nil and getmetatable(v) == opts.array_mt) then
            return "[]"
        end
        return "{}"
    end
    local n = sequence_length(v)
    if n then
        local items = shape and shape.items
        local out = {}
        for i = 1, n do out[i] = encode_value(v[i], items and items[i], opts, depth) end
        return "[" .. table_concat(out, ",") .. "]"
    end
    return encode_object(v, shape, opts, depth)
end


--- Encode value as JSON with the key order (and empty arrays) of shape.
-- shapes, optional, maps a table to the shape to use for it wherever it sits,
-- for values moved to another path (e.g. a schema an adapter relocates).
-- Returns the JSON text, or nil and an error.
function _M.encode(value, shape, shapes)
    local opts = {null = core.json and core.json.null, array_mt = core.json and core.json.array_mt,
                  shapes = shapes}
    local ok, out = pcall(encode_value, value, shape, opts, 0)
    if not ok then return nil, out end
    return out
end


return _M
