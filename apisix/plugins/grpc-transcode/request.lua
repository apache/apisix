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

local util   = require("apisix.plugins.grpc-transcode.util")
local core   = require("apisix.core")
local pb     = require("pb")
local bit    = require("bit")
local ngx    = ngx
local string = string
local table  = table
local pcall = pcall
local tonumber = tonumber
local req_read_body = ngx.req.read_body


local function map_request(proto, m, pb_option, default_values, request_table,
                           canonical_protojson, string_scalars)
    util.set_options(proto, pb_option, canonical_protojson)
    local message, err
    if canonical_protojson then
        message, err = util.map_protojson_message(m.input_type, default_values,
                                                  request_table, proto.json_names,
                                                  string_scalars)
    else
        message, err = util.map_message(m.input_type, default_values or {},
                                        request_table)
    end
    if not message then
        return nil, err
    end
    return pb.encode(m.input_type, message)
end


return function (proto, service, method, pb_option, deadline, default_values,
                 max_req_body_size, ctx, canonical_protojson)
    local m = util.find_method(proto, service, method)
    if not m then
        return false, "Undefined service method: " .. service .. "/" .. method
                      .. " end", 503
    end

    req_read_body()

    -- Read the input before switching pb.state: body IO does not need the
    -- shared protobuf state.
    local request_table, request_err, string_scalars
    if canonical_protojson then
        request_table, request_err, string_scalars =
            util.get_protojson_request_table(max_req_body_size, ctx)
    else
        request_table, request_err = util.get_request_table(max_req_body_size, ctx)
    end
    if not request_table then
        core.log.warn("grpc-transcode invalid request: ", request_err)
        local too_large = request_err and request_err:find("too large", 1, true)
        return false, "invalid request body", too_large and 413 or 400
    end

    local pb_old_state = pb.state(proto.pb_state)
    -- pb.state is restored even when mapping or encoding raises an error.
    local ok, encoded, map_err = pcall(map_request, proto, m, pb_option, default_values,
                                       request_table, canonical_protojson, string_scalars)
    pb.state(pb_old_state)

    if not ok then
        core.log.warn("grpc-transcode request encoding failed: ", encoded)
        return false, "failed to encode request data to protobuf", 400
    end
    if not encoded then
        core.log.warn("grpc-transcode request mapping failed: ", map_err)
        return false, "failed to encode request data to protobuf", 400
    end

    local size = #encoded
    local prefix = {
        string.char(0),
        string.char(bit.band(bit.rshift(size, 24), 0xFF)),
        string.char(bit.band(bit.rshift(size, 16), 0xFF)),
        string.char(bit.band(bit.rshift(size, 8), 0xFF)),
        string.char(bit.band(size, 0xFF))
    }

    local message = table.concat(prefix, "") .. encoded

    ngx.req.set_method(ngx.HTTP_POST)
    ngx.req.set_uri("/" .. service .. "/" .. method, false)
    ngx.req.set_uri_args({})
    ngx.req.set_body_data(message)

    local dl = tonumber(deadline)
    if dl~= nil and dl > 0 then
        ngx.req.set_header("grpc-timeout",  dl .. "m")
    end

    return true
end
