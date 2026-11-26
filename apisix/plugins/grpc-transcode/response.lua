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
local util        = require("apisix.plugins.grpc-transcode.util")
local grpc_proto  = require("apisix.plugins.grpc-transcode.proto")
local core   = require("apisix.core")
local pb     = require("pb")
local protojson = require("apisix.plugins.grpc-transcode.protojson")
local buffer_util = require("apisix.plugins.grpc-transcode.buffer")
local ngx    = ngx
local string = string
local ngx_decode_base64 = ngx.decode_base64
local ngx_encode_base64 = ngx.encode_base64
local setmetatable = setmetatable
local ipairs = ipairs
local pcall  = pcall
local error  = error
local type   = type
local tonumber = tonumber
local tostring = tostring


local function format_error(body, error_response_format)
    if error_response_format == "flat" then
        return body.error
    end
    return body
end


-- Error body for protojson = false: the decoded grpc-status-details-bin,
-- an error message when it cannot be decoded, the upstream body otherwise.
local function handle_error_response(status_detail_type, proto, error_response_format,
                                     buffer)
    local err_msg

    local grpc_status = ngx.header["grpc-status-details-bin"]
    if not grpc_status then
        ngx.arg[1] = buffer
        return nil
    end

    grpc_status = ngx_decode_base64(grpc_status)
    if grpc_status == nil then
        err_msg = "grpc-status-details-bin is not base64 format"
        ngx.arg[1] = err_msg
        return err_msg
    end

    local status_pb_state = grpc_proto.fetch_status_pb_state()
    local old_pb_state = pb.state(status_pb_state)

    local ok, decoded_grpc_status = pcall(pb.decode, "grpc_status.ErrorStatus", grpc_status)
    pb.state(old_pb_state)
    if not ok then
        err_msg = "failed to call pb.decode to decode grpc-status-details-bin"
        ngx.arg[1] = err_msg
        return err_msg .. ", err: " .. tostring(decoded_grpc_status)
    end

    if not decoded_grpc_status then
        err_msg = "failed to decode grpc-status-details-bin"
        ngx.arg[1] = err_msg
        return err_msg
    end

    local details = decoded_grpc_status.details
    if status_detail_type and details then
        local decoded_details = {}
        for _, detail in ipairs(details) do
            local pb_old_state = pb.state(proto.pb_state)
            local ok, err_or_value = pcall(pb.decode, status_detail_type, detail.value)
            pb.state(pb_old_state)
            if not ok then
                err_msg = "failed to call pb.decode to decode details in "
                       .. "grpc-status-details-bin"
                ngx.arg[1] = err_msg
                return err_msg .. ", err: " .. tostring(err_or_value)
            end

            if not err_or_value then
                err_msg = "failed to decode details in grpc-status-details-bin"
                ngx.arg[1] = err_msg
                return err_msg
            end

            core.table.insert(decoded_details, err_or_value)
        end

        decoded_grpc_status.details = decoded_details
    end

    local resp_body = format_error({error = decoded_grpc_status}, error_response_format)
    local response, err = core.json.encode(resp_body)
    if not response then
        err_msg = "failed to json_encode response body"
        ngx.arg[1] = err_msg
        return err_msg .. ", error: " .. tostring(err)
    end

    ngx.arg[1] = response
end


-- Error body for protojson = true: always JSON. Malformed status details fall
-- back to the status code and message from the trailers.
local function decode_protojson_detail(proto, pb_option, detail_type, bytes, opts)
    util.set_options(proto, pb_option, true)
    local value = pb.decode(detail_type, bytes)
    if not value then
        return nil
    end
    return protojson.from_proto(detail_type, value, nil, nil, proto.json_names, opts)
end


-- Error body for protojson = true: always JSON. Typed status details follow
-- the ProtoJSON mapping; untyped ones keep their type URL and base64 value.
-- Malformed status details fall back to the code and message from the
-- trailers.
local function protojson_error_response(status_detail_type, proto, error_response_format,
                                        pb_option, opts)
    local status = tonumber(ngx.header["grpc-status"] or "2") or 2
    local raw_message = ngx.header["grpc-message"] or "upstream gRPC error"
    -- gRPC percent-escapes are not x-www-form-urlencoded: preserve literal '+'
    -- and unescape only percent octets (including UTF-8 bytes).
    local message = raw_message:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end)
    local body = {error = {code = status, message = message}}

    local bytes = ngx.header["grpc-status-details-bin"]
    bytes = bytes and ngx_decode_base64(bytes)
    local status_state = bytes and grpc_proto.fetch_status_pb_state()
    if status_state then
        local previous = pb.state(status_state)
        local ok, decoded = pcall(pb.decode, "grpc_status.ErrorStatus", bytes)
        pb.state(previous)

        if ok and type(decoded) == "table" then
            local details = {}
            local detail_type = status_detail_type
            if detail_type and detail_type:sub(1, 1) ~= "." then
                detail_type = "." .. detail_type
            end

            for i, detail in ipairs(decoded.details or {}) do
                if detail_type then
                    previous = pb.state(proto.pb_state)
                    local good, value = pcall(decode_protojson_detail, proto, pb_option,
                                              detail_type, detail.value, opts)
                    pb.state(previous)
                    if not good or not value then
                        details = nil
                        break
                    end
                    details[i] = value
                else
                    details[i] = {
                        ["@type"] = detail.type_url,
                        value = ngx_encode_base64(detail.value or ""),
                    }
                end
            end

            if details then
                decoded.details = details[1] and setmetatable(details, core.json.array_mt)
                body = {error = decoded}
            end
        end
    end

    local payload, err = core.json.encode(format_error(body, error_response_format))
    if not payload then
        core.log.warn("grpc-transcode error JSON encode failed: ", err)
        payload = '{"error":{"message":"upstream gRPC error"}}'
    end
    ngx.arg[1] = payload
    return nil
end

return function(ctx, proto, service, method, pb_option, show_status_in_body,
                status_detail_type, max_resp_body_size, canonical_protojson,
                error_response_format, any_empty_format)
    -- Buffer *exactly*, never return the truncated first N bytes. On overflow
    -- abort downstream output: header_filter has already run, so an HTTP 502
    -- cannot be reliably sent from here. The caller raises an error.
    local buffer, overflow = buffer_util.push(ctx, ngx.arg[1], ngx.arg[2],
                                               max_resp_body_size or 67108864)
    ngx.arg[1] = nil
    if overflow then return overflow end
    if not buffer then return nil end

    if ngx.status >= 300 then
        if not show_status_in_body then
            ngx.arg[1] = ""
            return nil
        end
        if canonical_protojson then
            return protojson_error_response(status_detail_type, proto,
                                            error_response_format, pb_option, {
                any_empty_format = any_empty_format,
                implicit_presence = proto.implicit_presence,
            })
        end
        -- The status is already sent: report a broken status detail in the
        -- body and the error log, without aborting the response.
        local err = handle_error_response(status_detail_type, proto,
                                          error_response_format, buffer)
        if err then
            core.log.error("transform response error: ", err)
        end
        return nil
    end

    if buffer == "" then
        -- Empty gRPC bodies are valid only for error responses; a successful
        -- unary call must still carry a five-byte protobuf frame.
        return "empty successful gRPC body"
    end
    local m = util.find_method(proto, service, method)
    if not m then
        return "undefined service method: " .. service .. "/" .. method
    end

    -- gRPC uses a 5-byte prefix: compression flag + 32-bit BE length.
    -- The response must be exactly one uncompressed message frame. A
    -- streaming RPC therefore works only when it yields a single message;
    -- more messages abort the response instead of producing broken JSON.
    -- gRPC-Web is served by the grpc-web plugin, not by this transcoder.
    do
        if #buffer < 5 then
            return "invalid gRPC frame: header too short"
        end
        local compressed = buffer:byte(1)
        local a, b, c, d = buffer:byte(2, 5)
        local size = ((a * 256 + b) * 256 + c) * 256 + d
        if compressed ~= 0 or size ~= #buffer - 5 then
            return "invalid or unsupported gRPC frame"
        end
        buffer = buffer:sub(6)
    end

    local previous_state = pb.state(proto.pb_state)
    local ok, response_or_err = pcall(function()
        util.set_options(proto, pb_option, canonical_protojson)
        local decoded = pb.decode(m.output_type, buffer)
        if not decoded then error("failed to decode protobuf response") end
        -- WKT transformation happens while the correct descriptor is active.
        local normalized = decoded
        if canonical_protojson then
            normalized = protojson.from_proto(m.output_type, decoded, nil, nil,
                                              proto.json_names, {
                any_empty_format = any_empty_format,
                implicit_presence = proto.implicit_presence,
            })
        end
        local result, err = core.json.encode(normalized)
        if not result then
            error("failed to encode JSON response: " .. tostring(err))
        end
        return result
    end)
    pb.state(previous_state)
    if not ok then
        return "grpc-transcode response error: " .. tostring(response_or_err)
    end
    local response = response_or_err

    ngx.arg[1] = response
    return nil
end
