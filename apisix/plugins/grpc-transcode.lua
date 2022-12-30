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
local ngx         = ngx
local core        = require("apisix.core")
local schema_def  = require("apisix.schema_def")
local proto       = require("apisix.plugins.grpc-transcode.proto")
local request     = require("apisix.plugins.grpc-transcode.request")
local response    = require("apisix.plugins.grpc-transcode.response")


local plugin_name = "grpc-transcode"

local pb_option_def = {
    {   description = "enum as result",
        type = "string",
        enum = {"int64_as_number", "int64_as_string", "int64_as_hexstring"},
    },
    {   description = "int64 as result",
        type = "string",
        enum = {"enum_as_name", "enum_as_value"},
    },
    {   description ="default values option",
        type = "string",
        enum = {"auto_default_values", "no_default_values",
                "use_default_values", "use_default_metatable"},
    },
    {   description = "hooks option",
        type = "string",
        enum = {"enable_hooks", "disable_hooks" },
    },
}

local schema = {
    type = "object",
    properties = {
        proto_id  = schema_def.id_schema,
        service = {
            description = "the grpc service name",
            type        = "string"
        },
        method = {
            description = "the method name in the grpc service.",
            type    = "string"
        },
        deadline = {
            description = "deadline for grpc, millisecond",
            type        = "number",
            default     = 0
        },
        pb_option = {
            type = "array",
            items = { type="string", anyOf = pb_option_def },
            minItems = 1,
            default = {
                "enum_as_name",
                "int64_as_number",
                "auto_default_values",
                "disable_hooks",
            }
        },
        show_status_in_body = {
            description = "show decoded grpc-status-details-bin in response body",
            type        = "boolean",
            default     = false
        },
        -- https://github.com/googleapis/googleapis/blob/b7cb84f5d42e6dba0fdcc2d8689313f6a8c9d7b9/
        -- google/rpc/status.proto#L46
        status_detail_type = {
            description = "the message type of the grpc-status-details-bin's details part, "
                            .. "if not given, the details part will not be decoded",
            type        = "string",
        },
    },
    additionalProperties = true,
    required = { "proto_id", "service", "method" },
}

-- Based on https://cloud.google.com/apis/design/errors#handling_errors
local status_rel = {
    ["1"] = 499,    -- CANCELLED
    ["2"] = 500,    -- UNKNOWN
    ["3"] = 400,    -- INVALID_ARGUMENT
    ["4"] = 504,    -- DEADLINE_EXCEEDED
    ["5"] = 404,    -- NOT_FOUND
    ["6"] = 409,    -- ALREADY_EXISTS
    ["7"] = 403,    -- PERMISSION_DENIED
    ["8"] = 429,    -- RESOURCE_EXHAUSTED
    ["9"] = 400,    -- FAILED_PRECONDITION
    ["10"] = 409,   -- ABORTED
    ["11"] = 400,   -- OUT_OF_RANGE
    ["12"] = 501,   -- UNIMPLEMENTED
    ["13"] = 500,   -- INTERNAL
    ["14"] = 503,   -- UNAVAILABLE
    ["15"] = 500,   -- DATA_LOSS
    ["16"] = 401,   -- UNAUTHENTICATED
}

local _M = {
    version = 0.1,
    priority = 506,
    name = plugin_name,
    schema = schema,
}


function _M.init()
    proto.init()
end


function _M.destroy()
    proto.destroy()
end


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    return true
end


function _M.access(conf, ctx)
    core.log.info("conf: ", core.json.delay_encode(conf))

    local proto_id = conf.proto_id
    if not proto_id then
        core.log.error("proto id miss: ", proto_id)
        return
    end

    local proto_obj, err = proto.fetch(proto_id)
    if err then
        core.log.error("proto load error: ", err)
        return
    end

    local ok, err, err_code = request(proto_obj, conf.service,
                                      conf.method, conf.pb_option, conf.deadline)
    if not ok then
        core.log.error("transform request error: ", err)
        return err_code
    end

    ctx.proto_obj = proto_obj

end


function _M.header_filter(conf, ctx)
    if ngx.status >= 300 then
        return
    end

    ngx.header["Content-Type"] = "application/json"
    ngx.header.content_length = nil

    local headers = ngx.resp.get_headers()

    if headers["grpc-status"] ~= nil and headers["grpc-status"] ~= "0" then
        local http_status = status_rel[headers["grpc-status"]]
        if http_status ~= nil then
            ngx.status = http_status
        else
            ngx.status = 599
        end
    else
        -- The error response body does not contain grpc-status and grpc-message
        ngx.header["Trailer"] = {"grpc-status", "grpc-message"}
    end

end


function _M.body_filter(conf, ctx)
    if ngx.status >= 300 and not conf.show_status_in_body then
        return
    end

    local proto_obj = ctx.proto_obj
    if not proto_obj then
        return
    end

    local err = response(ctx, proto_obj, conf.service, conf.method, conf.pb_option,
                         conf.show_status_in_body, conf.status_detail_type)
    if err then
        core.log.error("transform response error: ", err)
        return
    end
end


return _M
