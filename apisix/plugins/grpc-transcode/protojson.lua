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

-- ProtoJSON mapping between JSON values and lua-protobuf message tables,
-- used when the route enables `protojson`. The caller must activate the
-- pb.State of the route's proto before calling the public functions.
local core = require("apisix.core")
local ngx = ngx
local pb = require("pb")
local wkt = require("apisix.plugins.grpc-transcode.wkt")
local json = core.json
local null = json.null
local array_mt = json.array_mt
local type, pairs, ipairs, next = type, pairs, ipairs, next
local setmetatable, getmetatable = setmetatable, getmetatable
local error, pcall, tonumber, tostring = error, pcall, tonumber, tostring
local floor, abs, huge = math.floor, math.abs, math.huge
local concat = table.concat
local byte, sub, format, upper = string.byte, string.sub, string.format, string.upper
local new_tab
do
    -- LuaJIT/OpenResty preallocation; plain Lua (offline tests) falls back.
    local ok, table_new = pcall(require, "table.new")
    new_tab = ok and table_new or function() return {} end
end
local VALUE, STRUCT, LIST = ".google.protobuf.Value", ".google.protobuf.Struct",
                            ".google.protobuf.ListValue"
local ANY, EMPTY = ".google.protobuf.Any", ".google.protobuf.Empty"

local M = {}
local MAX_DEPTH = 64
local int64_types = {
    int64 = true, uint64 = true, sint64 = true,
    fixed64 = true, sfixed64 = true,
}
local MAX_SAFE_JSON_INTEGER = 9007199254740991
local int32_min = {int32 = -2147483648, sint32 = -2147483648, sfixed32 = -2147483648,
                   uint32 = 0, fixed32 = 0}
local int32_max = {int32 = 2147483647, sint32 = 2147483647, sfixed32 = 2147483647,
                   uint32 = 4294967295, fixed32 = 4294967295}
local FLOAT_MAX = 3.4028234663852886e38
local function fail(path, msg)
    error("ProtoJSON " .. path .. ": " .. msg, 0)
end

-- Cache reflected fields by pb.State (weak keys): no descriptor reflection on
-- every message instance, and no cross-proto field collisions. Everything the
-- conversion loops need per field is resolved here once per (state, type).
local descriptor_cache = setmetatable({}, {__mode = "k"})

-- A named replacement instead of a function literal: a child closure would
-- put UCLO (not compiled by LuaJIT) before every return of its parent.
local function camel_case(name)
    return (name:gsub("_([a-z])", upper))
end

local function types_for_state()
    local state = pb.state()
    local types = descriptor_cache[state]
    if not types then
        types = {}
        descriptor_cache[state] = types
    end
    return types
end

local function load_fields(types, ft)
    local fields = {}
    for name, _, field_type, _, label, oneof in pb.fields(ft) do
        local _, _, kind = pb.type(field_type)
        local info = {name=name, field_type=field_type, label=label,
            kind=kind, oneof=oneof,
            camel=camel_case(name),
            repeated = label == "repeated" or label == "packed",
            -- plain: the decoded Lua value is already its ProtoJSON value.
            plain = kind ~= "message" and kind ~= "map" and not int64_types[field_type]
                and field_type ~= "double" and field_type ~= "float"
                and field_type ~= "bytes",
            -- json_name memoized per names table; false never matches one.
            json = false, json_for = false}
        if kind == "map" then
            local _, _, value_type = pb.field(field_type, "value")
            local _, _, key_type = pb.field(field_type, "key")
            local _, _, value_kind = pb.type(value_type)
            info.value_type, info.key_type, info.value_kind = value_type, key_type, value_kind
        elseif kind == "enum" then
            info.enum_zero = pb.enum(field_type, 0)
        end
        if oneof then fields.oneofs = true end
        fields[#fields+1] = info
    end
    types[ft] = fields
    return fields
end

local function json_name_of(desc, type_names)
    if desc.json_for ~= type_names then
        desc.json = (type_names and type_names[desc.name]) or desc.camel
        desc.json_for = type_names
    end
    return desc.json
end

-- One conversion: the descriptor cache of the active pb.State, the trail of
-- field names used to report error locations, and the caller's metadata.
-- Every public call gets its own context, so an independent conversion that
-- starts while another one is running (e.g. from a lua-protobuf hook) cannot
-- disturb it. Error locations are rebuilt from the trail only when an error
-- is raised instead of concatenating a path string for every field.
local function new_context(root, depth, names, opts, string_scalars)
    local trail = {[0] = root}
    for i = 1, depth do trail[i] = false end
    return {
        types = types_for_state(),
        trail = trail,
        names = names,
        implicit = opts and opts.implicit_presence,
        opts = opts,
        string_scalars = string_scalars,
    }
end

local function fail_at(ctx, depth, msg)
    local trail, parts = ctx.trail, {}
    for i = 0, depth do
        local seg = trail[i]
        if type(seg) == "number" then
            parts[#parts+1] = "[" .. seg .. "]"
        elseif seg then
            parts[#parts+1] = (i > 0 and "." or "") .. tostring(seg)
        end
    end
    error("ProtoJSON " .. concat(parts) .. ": " .. msg, 0)
end


local function wire_int64(ctx, v, ft, depth)
    if type(v) == "number" then
        if v ~= floor(v) or abs(v) > MAX_SAFE_JSON_INTEGER then
            fail_at(ctx, depth, "64-bit integer must be a decimal string")
        end
        v = format("%.0f", v)
    end
    if type(v) ~= "string" or not v:match("^%-?%d+$") then
        fail_at(ctx, depth, "invalid decimal 64-bit integer")
    end
    local neg = v:sub(1,1) == "-"
    local digits = (neg and v:sub(2) or v):gsub("^0+", "")
    if digits == "" then digits = "0"; neg = false end
    local unsigned = ft == "uint64" or ft == "fixed64"
    local limit = unsigned and "18446744073709551615" or
        (neg and "9223372036854775808" or "9223372036854775807")
    if (unsigned and neg) or #digits > #limit or
       (#digits == #limit and digits > limit) then
        fail_at(ctx, depth, "64-bit integer out of range")
    end
    return "#" .. (neg and "-" or "") .. digits
end

local function integer_map_key(k)
    if type(k) == "string" then
        -- int64_as_string should preserve the exact decimal spelling.
        if byte(k, 1) == 35 then return sub(k, 2) end
        return k
    end
    if type(k) ~= "number" or k ~= floor(k) or abs(k) > MAX_SAFE_JSON_INTEGER then
        fail("map", "integer map key cannot be represented without precision loss")
    end
    return format("%.0f", k)
end

-- Quoted numbers use the JSON number spelling: hex and Lua-specific number
-- spellings stay out.
local function number_string(v)
    return v:match("^%-?%d+%.?%d*$") or v:match("^%-?%d+%.?%d*[eE][+-]?%d+$")
end

local function parse_decimal_float(ctx, ft, v, depth)
    local out = v
    if type(v) == "string" then
        if v == "NaN" then return 0/0 end
        if v == "Infinity" then return huge end
        if v == "-Infinity" then return -huge end
        -- Strings are legal for float/double in ProtoJSON (including exponent).
        out = number_string(v) and tonumber(v)
    elseif type(v) ~= "number" then
        out = nil
    end
    if not out then fail_at(ctx, depth, "invalid floating-point value") end
    -- Only the quoted names above stand for infinity; a finite number must fit
    -- the field, lua-protobuf would turn a too large float into infinity.
    if out == huge or out == -huge or (ft == "float" and abs(out) > FLOAT_MAX) then
        fail_at(ctx, depth, "floating-point value out of range")
    end
    return out
end

-- 32-bit integers come as JSON numbers or, as ProtoJSON allows, as quoted
-- numbers. lua-protobuf would truncate a fraction and wrap a value that does
-- not fit, so both are checked here.
local function int32_to(ctx, ft, v, depth)
    local n = v
    if type(v) == "string" then
        n = number_string(v) and tonumber(v)
    elseif type(v) ~= "number" then
        n = nil
    end
    if not n or n ~= floor(n) then fail_at(ctx, depth, "invalid 32-bit integer") end
    if n < int32_min[ft] or n > int32_max[ft] then
        fail_at(ctx, depth, "32-bit integer out of range")
    end
    return n
end

-- Enums take a value name or an int32 number. Query and form values are
-- strings, so there a quoted number is accepted as well.
local function enum_to(ctx, ft, v, depth)
    if type(v) == "string" then
        if ctx.string_scalars and number_string(v) then
            v = tonumber(v)
        else
            -- pb.enum() would also resolve a quoted number; value names never
            -- look like one.
            local n = not number_string(v) and pb.enum(ft, v)
            if not n then fail_at(ctx, depth, "unknown enum value name") end
            return n
        end
    end
    if type(v) ~= "number" or v ~= floor(v) or v < -2147483648 or v > 2147483647 then
        fail_at(ctx, depth, "enum must be a value name or a 32-bit integer")
    end
    return v
end


local function array(t)
    if getmetatable(t) == array_mt then return true end
    -- The request decoder tags even empty arrays. This fallback is needed for
    -- Lua tables coming from non-JSON code paths, e.g. repeated form fields.
    if next(t) == nil then return false end
    local n, count = #t, 0
    for k in pairs(t) do
        if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then
            return false
        end
        count = count + 1
    end
    return count == n
end

local to_proto, from_proto

-- Request path. Like the response path below, the hot functions create no
-- closures (FNEW and UCLO abort LuaJIT traces) and take field kinds from the
-- descriptor cache instead of calling pb.type() for every field.
local value_to

local function scalar_to(ctx, ft, kind, v, depth)
    if kind == "enum" then return enum_to(ctx, ft, v, depth) end
    if ft == "double" or ft == "float" then
        return parse_decimal_float(ctx, ft, v, depth)
    end
    if ft == "string" then
        if type(v) ~= "string" then fail_at(ctx, depth, "expected string") end
        return v
    end
    if ft == "bool" then
        if type(v) == "boolean" then return v end
        if ctx.string_scalars then
            if v == "true" then return true end
            if v == "false" then return false end
        end
        fail_at(ctx, depth, "boolean must be true or false")
    end
    if int32_min[ft] then
        return int32_to(ctx, ft, v, depth)
    end
    if ft == "bytes" then
        if type(v) ~= "string" then fail_at(ctx, depth, "bytes must be base64 string") end
        local raw = ngx.decode_base64(v)
        if raw == nil then fail_at(ctx, depth, "invalid base64 bytes") end
        return raw
    end
    if int64_types[ft] then
        return wire_int64(ctx, v, ft, depth)
    end
    return v
end

local function field_to(ctx, ft, kind, v, depth)
    if v == null then
        if ft == VALUE then return {null_value = 0} end
        return nil
    end
    if kind == "message" then return to_proto(ctx, ft, v, depth) end
    return scalar_to(ctx, ft, kind, v, depth)
end

local function struct_to(ctx, v, depth)
    if depth > MAX_DEPTH then fail_at(ctx, depth, "nesting exceeds 64 JSON levels") end
    if type(v) ~= "table" or array(v) then fail_at(ctx, depth, "expected JSON object") end
    local trail, fields = ctx.trail, {}
    for k, item in pairs(v) do
        if type(k) ~= "string" then fail_at(ctx, depth, "object key is not a string") end
        trail[depth+1] = k
        fields[k] = value_to(ctx, item, depth+1)
    end
    return {fields = fields}
end

local function list_to(ctx, v, depth)
    if depth > MAX_DEPTH then fail_at(ctx, depth, "nesting exceeds 64 JSON levels") end
    if type(v) ~= "table" or not array(v) then fail_at(ctx, depth, "expected JSON array") end
    local trail = ctx.trail
    local values = setmetatable(new_tab(#v, 0), array_mt)
    for i, item in ipairs(v) do
        trail[depth+1] = i
        values[i] = value_to(ctx, item, depth+1)
    end
    return {values = values}
end

function value_to(ctx, v, depth)
    if depth > MAX_DEPTH then fail_at(ctx, depth, "nesting exceeds 64 JSON levels") end
    if v == null then return {null_value = 0} end
    local kind = type(v)
    if kind == "string" then return {string_value = v} end
    if kind == "boolean" then return {bool_value = v} end
    if kind == "number" then return {number_value = v} end
    if kind == "table" then
        if array(v) then return {list_value = list_to(ctx, v, depth)} end
        return {struct_value = struct_to(ctx, v, depth)}
    end
    fail_at(ctx, depth, "unsupported JSON value type " .. kind)
end

-- Wrapper WKTs encode one scalar through this callback and never recurse, so
-- a single static function serves all of them. Its context is set right
-- before each wkt.to_proto() call; nothing in between runs pb.encode() or
-- pb.decode(), so no lua-protobuf hook can start another conversion there.
local wrapper_ctx, wrapper_depth
local function wrapper_scalar_to(t, data)
    return field_to(wrapper_ctx, t, nil, data, wrapper_depth)
end

-- Any is the only WKT that encodes a nested message, so it alone needs a
-- closure; it lives here to keep to_proto free of child functions. Any never
-- encodes a bare scalar, hence no scalar callback.
local function any_to(ctx, v, depth)
    return wkt.to_proto(ANY, v, nil, function(t, data)
        ctx.trail[depth+1] = false
        return to_proto(ctx, t, data, depth+1)
    end, null, ctx.opts)
end

function to_proto(ctx, ft, v, depth)
    if depth > MAX_DEPTH then fail_at(ctx, depth, "nesting exceeds 64 JSON levels") end
    if ft == VALUE then return value_to(ctx, v, depth) end
    if ft == STRUCT then return struct_to(ctx, v, depth) end
    if ft == LIST then return list_to(ctx, v, depth) end
    if ft == ANY then return any_to(ctx, v, depth) end
    local trail = ctx.trail
    if ft == EMPTY or wkt.is_custom(ft) then
        -- Timestamp, Duration, FieldMask, Empty and wrappers: no recursion.
        trail[depth+1] = false
        wrapper_ctx, wrapper_depth = ctx, depth+1
        return wkt.to_proto(ft, v, wrapper_scalar_to, nil, null, ctx.opts)
    end
    if type(v) ~= "table" or array(v) then fail_at(ctx, depth, "expected message object") end
    local types = ctx.types
    local fields = types[ft] or load_fields(types, ft)
    local count = #fields
    local out = new_tab(0, count)
    local type_names = ctx.names and ctx.names[ft]
    local child = depth + 1
    -- members of a oneof seen so far; allocated only for messages that have one
    local oneofs = fields.oneofs and {}
    for i = 1, count do
        local desc = fields[i]
        local name, field_type = desc.name, desc.field_type
        local item = v[name]
        local json_name = json_name_of(desc, type_names)
        if json_name ~= name then
            local other = v[json_name]
            if item == nil then
                item = other
            elseif other ~= nil then
                trail[child] = name
                fail_at(ctx, child, "field is set twice, as " .. name .. " and " .. json_name)
            end
        end
        if item ~= nil and (item ~= null or field_type == VALUE) then
            trail[child] = name
            local oneof = oneofs and desc.oneof
            if oneof then
                if oneofs[oneof] then
                    fail_at(ctx, child, "oneof " .. oneof .. " is already set by "
                                        .. oneofs[oneof])
                end
                oneofs[oneof] = name
            end
            local kind = desc.kind
            if kind == "map" then
                if type(item) ~= "table" or array(item) then
                    fail_at(ctx, child, "expected map object")
                end
                local key_type = desc.key_type
                local value_type, value_kind = desc.value_type, desc.value_kind
                local mapped = {}
                for k, mv in pairs(item) do
                    local wire_key = k
                    if key_type == "bool" then
                        if k ~= "true" and k ~= "false" then
                            fail_at(ctx, child, "invalid bool map key")
                        end
                        wire_key = k == "true"
                    elseif key_type ~= "string" then
                        if type(k) ~= "string" or not k:match("^%-?%d+$") then
                            fail_at(ctx, child, "invalid integer map key")
                        end
                        if int64_types[key_type] then
                            -- lua-protobuf accepts #decimal strings for 64-bit
                            -- numbers (including map keys), preserving full range.
                            wire_key = wire_int64(ctx, k, key_type, child)
                        else
                            wire_key = tonumber(k)
                            if not wire_key or wire_key ~= floor(wire_key) then
                                fail_at(ctx, child, "invalid integer map key")
                            end
                            if wire_key < int32_min[key_type] or
                               wire_key > int32_max[key_type] then
                                fail_at(ctx, child, "integer map key out of range")
                            end
                        end
                    end
                    mapped[wire_key] = field_to(ctx, value_type, value_kind, mv, child)
                end
                out[name] = mapped
            elseif desc.repeated then
                if type(item) ~= "table" or not array(item) then
                    fail_at(ctx, child, "expected repeated array")
                end
                local mapped = setmetatable(new_tab(#item, 0), array_mt)
                for j, mv in ipairs(item) do
                    mapped[j] = field_to(ctx, field_type, kind, mv, child)
                end
                out[name] = mapped
            else
                out[name] = field_to(ctx, field_type, kind, item, child)
            end
        end
    end
    return out
end

-- Response path. The hot functions below create no closures: FNEW and UCLO
-- are not compiled by LuaJIT and would abort every trace through this loop.
local function scalar_from(ft, v)
    if ft == "double" or ft == "float" then
        if v ~= v then return "NaN" end
        if v == huge then return "Infinity" end
        if v == -huge then return "-Infinity" end
        return v
    end
    if ft == "bytes" then return ngx.encode_base64(v) end
    if int64_types[ft] then
        if type(v) == "string" then
            if byte(v, 1) == 35 then return sub(v, 2) end
            return v
        end
        return format("%.0f", v)
    end
    return v
end

-- Default value of a proto3 field without presence tracking. -0.0 differs
-- from the default on the wire and is kept.
local function is_default(desc, v)
    if v == false or v == "" then return true end
    if v == 0 then return 1 / v > 0 end
    return desc.enum_zero ~= nil and v == desc.enum_zero
end

local value_from

local function struct_from(ctx, v, depth)
    local trail, out = ctx.trail, {}
    local entries = v.fields
    if entries then
        for k, item in pairs(entries) do
            trail[depth+1] = k
            out[k] = value_from(ctx, item, depth+1)
        end
    end
    return out
end

local function list_from(ctx, v, depth)
    local trail = ctx.trail
    local values = v.values
    local n = values and #values or 0
    local out = setmetatable(new_tab(n, 0), array_mt)
    for i = 1, n do
        trail[depth+1] = i
        out[i] = value_from(ctx, values[i], depth+1)
    end
    return out
end

function value_from(ctx, v, depth)
    if depth > MAX_DEPTH then fail_at(ctx, depth, "nesting exceeds 64 JSON levels") end
    if type(v) ~= "table" then fail_at(ctx, depth, "malformed Value") end
    if v.null_value ~= nil then return null end
    local scalar = v.string_value
    if scalar ~= nil then return scalar end
    scalar = v.number_value
    if scalar ~= nil then return scalar end
    scalar = v.bool_value
    if scalar ~= nil then return scalar end
    if v.struct_value ~= nil then return struct_from(ctx, v.struct_value, depth) end
    if v.list_value ~= nil then return list_from(ctx, v.list_value, depth) end
    return null
end

-- Any is the only WKT that descends into another message, so it is the only
-- one needing a callback; the closure lives here, not in from_proto.
local function any_from(ctx, v, depth)
    return wkt.from_proto(ANY, v, scalar_from, function(t, data)
        ctx.trail[depth+1] = false
        return from_proto(ctx, t, data, depth+1)
    end, ctx.opts)
end

local function value_of(ctx, ft, kind, v, depth)
    if kind == "message" then return from_proto(ctx, ft, v, depth) end
    return scalar_from(ft, v)
end

function from_proto(ctx, ft, v, depth)
    if depth > MAX_DEPTH then fail_at(ctx, depth, "nesting exceeds 64 JSON levels") end
    if ft == VALUE then return value_from(ctx, v, depth) end
    if ft == STRUCT then return struct_from(ctx, v, depth) end
    if ft == LIST then return list_from(ctx, v, depth) end
    if ft == ANY then return any_from(ctx, v, depth) end
    if ft == EMPTY or wkt.is_custom(ft) then
        return wkt.from_proto(ft, v, scalar_from, nil, ctx.opts)
    end
    if type(v) ~= "table" then return v end
    local types, trail = ctx.types, ctx.trail
    local fields = types[ft] or load_fields(types, ft)
    local count = #fields
    local out = new_tab(0, count)
    local type_names = ctx.names and ctx.names[ft]
    local no_presence = ctx.implicit and ctx.implicit[ft]
    local child = depth + 1
    for i = 1, count do
        local desc = fields[i]
        local name = desc.name
        local item = v[name]
        if item ~= nil then
            local json_name = json_name_of(desc, type_names)
            trail[child] = name
            local kind = desc.kind
            if kind == "map" then
                local mapped = {}
                local key_type = desc.key_type
                local value_type, value_kind = desc.value_type, desc.value_kind
                for k, mv in pairs(item) do
                    local json_key
                    if key_type == "bool" then
                        json_key = k and "true" or "false"
                    elseif key_type == "string" then
                        json_key = k
                    else
                        json_key = integer_map_key(k)
                    end
                    mapped[json_key] = value_of(ctx, value_type, value_kind, mv, child)
                end
                if next(mapped) ~= nil then out[json_name] = mapped end
            elseif desc.repeated then
                local n = #item
                if n > 0 then
                    local mapped = setmetatable(new_tab(n, 0), array_mt)
                    if desc.plain then
                        for j = 1, n do mapped[j] = item[j] end
                    else
                        local field_type = desc.field_type
                        for j = 1, n do
                            mapped[j] = value_of(ctx, field_type, kind, item[j], child)
                        end
                    end
                    out[json_name] = mapped
                end
            -- The decoder keeps what is on the wire (no_default_values).
            -- ProtoJSON omits a proto3 field without presence tracking when
            -- it holds its default value, even if a sender encoded it.
            elseif not (no_presence and no_presence[name] and is_default(desc, item)) then
                if desc.plain then
                    out[json_name] = item
                else
                    out[json_name] = value_of(ctx, desc.field_type, kind, item, child)
                end
            end
        end
    end
    return out
end

-- Public entry points. `path` is the location prefix reported in error
-- messages (defaults to the type name); `depth` is the nesting level the
-- conversion starts at. opts.implicit_presence lists, per message type, the
-- proto3 fields without presence tracking (see proto.lua).
function M.to_proto(ft, value, depth, path, names, string_scalars, opts)
    depth = depth or 0
    local ctx = new_context(path or ft, depth, names, opts, string_scalars)
    return to_proto(ctx, ft, value, depth)
end

function M.from_proto(ft, value, depth, path, names, opts)
    depth = depth or 0
    local ctx = new_context(path or ft, depth, names, opts)
    return from_proto(ctx, ft, value, depth)
end

-- Legacy mode must never normalize WKT or field names.
function M.maybe_from_proto(ft, value, force, names, opts)
    if not force then return value end
    return M.from_proto(ft, value, nil, nil, names, opts)
end

return M
