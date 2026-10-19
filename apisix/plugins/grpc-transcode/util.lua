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
local core              = require("apisix.core")
local proto_fake_file   = require("apisix.plugins.grpc-transcode.proto").proto_fake_file
local protojson         = require("apisix.plugins.grpc-transcode.protojson")
local json              = core.json
local pb                = require("pb")
local ngx               = ngx
local string            = string
local ipairs            = ipairs
local pairs             = pairs
local pcall             = pcall
local tonumber          = tonumber
local tostring          = tostring
local type              = type
local getmetatable      = getmetatable
local setmetatable      = setmetatable
local sort              = table.sort
local concat            = table.concat
-- Share APISIX' cjson.safe instance: core.json has already configured
-- decode_array_with_array_mt(true). A cjson.new() instance can have a
-- different array_mt identity, causing [] to be misidentified as {}.
local json_decoder      = require("cjson.safe")


local _M = {version = 0.1}


function _M.find_method(proto, service, method)
    local loaded = proto and proto[proto_fake_file]
    if type(loaded) ~= "table" or type(loaded.index) ~= "table" then
        core.log.error("compiled proto not found")
        return nil
    end

    local methods = loaded.index[service]
    if type(methods) ~= "table" then
        core.log.error("compiled proto service not found")
        return nil
    end

    local res = methods[method]
    if not res then
        core.log.error("compiled proto method not found")
        return nil
    end

    return res
end


local option_category = {
    enum_as_name = "enum", enum_as_value = "enum",
    int64_as_number = "int64", int64_as_string = "int64", int64_as_hexstring = "int64",
    auto_default_values = "default", no_default_values = "default",
    use_default_values = "default", use_default_metatable = "default",
    enable_hooks = "hooks", disable_hooks = "hooks",
}
-- What a fresh pb.State uses, and therefore what a route gets for a category
-- its pb_option does not list.
local default_options = {
    {"enum", "enum_as_name"}, {"int64", "int64_as_number"},
    {"default", "auto_default_values"}, {"hooks", "disable_hooks"},
}
-- ProtoJSON needs field presence as it is on the wire (no synthesized
-- defaults), exact 64-bit integers and enum names, whatever pb_option lists.
local protojson_options = {
    {"default", "no_default_values"}, {"int64", "int64_as_string"},
    {"enum", "enum_as_name"},
}

-- Sorted copy and key of a route's pb_option; the route configuration itself
-- is never modified.
local option_lists = setmetatable({}, {__mode = "k"})
local no_options = {}

local function option_list(options)
    local cached = option_lists[options]
    if not cached then
        local list = {}
        for i, opt in ipairs(options) do
            list[i] = opt
        end
        sort(list)
        cached = {list = list, key = concat(list, ",")}
        option_lists[options] = cached
    end
    return cached
end


-- Options live in the pb.State, which all routes using the same proto share.
-- They are applied only when the route's list differs from the one applied
-- last; categories the list does not mention go back to their defaults, so
-- a route never inherits an option set for another route.
function _M.set_options(proto, options, canonical_protojson)
    local opts = option_list(options or no_options)
    local key = canonical_protojson and opts.key .. "|protojson" or opts.key
    if proto and proto.options_key == key then
        return
    end

    local current = proto and proto.options_state
    if not current then
        current = {}
        if proto then
            -- a fresh pb.State starts with the default options; without a
            -- proto object the state is unknown and every category is set
            for _, item in ipairs(default_options) do
                current[item[1]] = item[2]
            end
        end
    end

    local listed = {}
    for _, opt in ipairs(opts.list) do
        pb.option(opt)
        local category = option_category[opt]
        if category then
            current[category] = opt
            listed[category] = true
        end
    end

    for _, item in ipairs(default_options) do
        local category, opt = item[1], item[2]
        if not listed[category] and current[category] ~= opt then
            pb.option(opt)
            current[category] = opt
        end
    end

    if canonical_protojson then
        for _, item in ipairs(protojson_options) do
            local category, opt = item[1], item[2]
            if current[category] ~= opt then
                pb.option(opt)
                current[category] = opt
            end
        end
    end

    if proto then
        proto.options_state = current
        proto.options_key = key
    end
end


local function is_too_large(err)
    return err:find("greater", 1, true) or err:find("too large", 1, true)
end


-- Request input for protojson = false. Same sources and precedence as before
-- the ProtoJSON mode was added: a JSON body for POST/PUT/PATCH, otherwise
-- (or when the body is not valid JSON) form arguments for POST and the query
-- string for everything else.
local function get_request_table(max_req_body_size, ctx)
    local method = ngx.req.get_method()
    local content_type = ngx.req.get_headers()["Content-Type"]
    if type(content_type) ~= "string" then
        content_type = ""
    end

    if string.find(content_type, "application/json", 1, true) and
        (method == "POST" or method == "PUT" or method == "PATCH")
    then
        local req_body, err = core.request.get_body(max_req_body_size, ctx)
        if not req_body and err and max_req_body_size and is_too_large(err) then
            return nil, "request body too large"
        end

        if req_body then
            local data = json.decode(req_body)
            if data then
                return data
            end
        end
    end

    if method == "POST" then
        return ngx.req.get_post_args()
    end

    return ngx.req.get_uri_args()
end

_M.get_request_table = get_request_table


-- Request input for protojson = true: a JSON object for every method that
-- carries a JSON body, strict form or query otherwise. The third value tells
-- whether scalars arrived as strings (query/form) and may be coerced.
function _M.get_protojson_request_table(max_req_body_size, ctx)
    local method = ngx.req.get_method()
    local content_type = ngx.req.get_headers()["Content-Type"] or ""
    local mime = type(content_type) == "string"
        and content_type:lower():match("^%s*([^;%s]+)")
    if method ~= "GET" and method ~= "HEAD" and mime == "application/json" then
        local body, err = core.request.get_body(max_req_body_size, ctx)
        if err then
            -- Never parse an unread body as {}.
            if is_too_large(err) then
                return nil, "request body too large"
            end
            return nil, "unable to read JSON request body"
        end

        if not body or body == "" then
            return {}, nil, false
        end

        local data, decode_err = json_decoder.decode(body)
        if not data then
            return nil, "invalid JSON request: " .. tostring(decode_err)
        end
        if type(data) ~= "table" or getmetatable(data) == json.array_mt then
            return nil, "JSON request must be an object"
        end
        return data, nil, false
    end

    if method == "POST" and mime == "application/x-www-form-urlencoded" then
        local data, err = ngx.req.get_post_args()
        if err then
            return nil, "invalid or truncated form data: " .. tostring(err)
        end
        return data or {}, nil, true
    end

    local data, err = ngx.req.get_uri_args()
    if err then
        return nil, "invalid or truncated query parameters: " .. tostring(err)
    end
    return data or {}, nil, true
end


local function get_from_request(request_table, name, kind)
    if not request_table then
        return nil
    end

    local prefix = kind:sub(1, 3)
    if prefix == "int" then
        if request_table[name] then
            if kind == "int64" then
                return request_table[name]
            else
                return tonumber(request_table[name])
            end
        end
    end

    return request_table[name]
end


-- Field mapping for protojson = false, unchanged: field names as in the
-- .proto file, Lua values passed to lua-protobuf as they are.
function _M.map_message(field, default_values, request_table, real_key)
    if not pb.type(field) then
        return nil, "Field " .. field .. " is not defined"
    end

    local request = {}
    local sub, err
    if not request_table then
        request_table = get_request_table()
    end

    for name, _, field_type in pb.fields(field) do
        local _, _, ty = pb.type(field_type)
        if ty ~= "enum" and field_type:sub(1, 1) == "." then
            if request_table[name] == nil then
                sub = default_values and default_values[name]
            elseif core.table.isarray(request_table[name]) then
                local sub_array = core.table.new(#request_table[name], 0)
                for i, value in ipairs(request_table[name]) do
                    local sub_array_obj
                    if type(value) == "table" then
                        sub_array_obj, err = _M.map_message(field_type,
                                default_values and default_values[name], value)
                        if err then
                            return nil, err
                        end
                    else
                        sub_array_obj = value
                    end
                    sub_array[i] = sub_array_obj
                end
                sub = sub_array
            else
                if ty == "map" then
                    for k, v in pairs(request_table[name]) do
                        local tbl, err = _M.map_message(field_type,
                            default_values and default_values[name],
                            request_table[name], k)
                        if err then
                            return nil, err
                        end
                        if not sub then
                            sub = {}
                        end
                        sub[k] = tbl[k]
                    end
                else
                    sub, err = _M.map_message(field_type,
                        default_values and default_values[name],
                        request_table[name])
                    if err then
                        return nil, err
                    end
                end
            end

            request[name] = sub
        else
            if real_key then
                name = real_key
            end
            request[name] = get_from_request(request_table, name, field_type)
                                or (default_values and default_values[name])
        end
    end
    return request
end


-- Field mapping for protojson = true: ProtoJSON input rules.
function _M.map_protojson_message(field, default_values, request_table, names,
                                  string_scalars, opts)
    if not pb.type(field) then
        return nil, "Field " .. tostring(field) .. " is not defined"
    end
    if type(request_table) ~= "table" then
        return nil, "request must be a JSON object"
    end

    -- Route defaults never overwrite values sent by the client, including
    -- false, 0 and empty strings.
    if default_values then
        local merged = {}
        for k, v in pairs(default_values) do merged[k] = v end
        for k, v in pairs(request_table) do merged[k] = v end
        request_table = merged
    end

    local ok, result = pcall(protojson.to_proto, field, request_table, nil, nil,
                             names, string_scalars, opts)
    if not ok then
        return nil, result
    end
    return result
end


return _M
