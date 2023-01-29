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
local json              = core.json
local pb                = require("pb")
local ngx               = ngx
local string            = string
local table             = table
local ipairs            = ipairs
local pairs             = pairs
local tonumber          = tonumber
local type              = type


local _M = {version = 0.1}


function _M.find_method(proto, service, method)
    local loaded = proto[proto_fake_file]
    if type(loaded) ~= "table" then
        core.log.error("compiled proto not found")
        return nil
    end

    if type(loaded.index[service]) ~= "table" then
        core.log.error("compiled proto service not found")
        return nil
    end

    local res = loaded.index[service][method]
    if not res then
        core.log.error("compiled proto method not found")
        return nil
    end

    -- restore pb state
    pb.state(proto.pb_state)
    return res
end


function _M.set_options(proto, options)
    local cur_opts = proto.options
    if cur_opts then
        if cur_opts == options then
            -- same route
            return
        end

        local same = true
        table.sort(options)
        for i, v in ipairs(options) do
            if cur_opts[i] ~= v then
                same = false
                break
            end
        end

        if same then
            -- Routes have the same configuration, usually the default one.
            -- As this is a small optimization, we don't care about routes have different
            -- configuration but have the same effect eventually.
            return
        end
    else
        table.sort(options)
    end

    for _, opt in ipairs(options) do
        pb.option(opt)
    end

    proto.options = options
end


local function get_request_table()
    local method = ngx.req.get_method()
    local content_type = ngx.req.get_headers()["Content-Type"] or ""
    if string.find(content_type, "application/json", 1, true) and
        (method == "POST" or method == "PUT" or method == "PATCH")
    then
        local req_body, _ = core.request.get_body()
        if req_body then
            local data, _ = json.decode(req_body)
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


return _M
