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

local ngx = ngx
local core = require("apisix.core")
local uuid = require("resty.jit-uuid")
local nanoid = require("nanoid")
local math_random = math.random
local str_byte = string.byte
local ffi = require "ffi"

local plugin_name = "request-id"

local schema = {
    type = "object",
    properties = {
        header_name = {type = "string", default = "X-Request-Id"},
        include_in_response = {type = "boolean", default = true},
        algorithm = {
            type = "string",
            enum = {"uuid", "nanoid", "range_id"},
            default = "uuid"
        },
        range_id = {
            type = "object",
            properties = {
                length = {
                    type = "integer",
                    minimum = 6,
                    default = 16
                },
                char_set = {
                    type = "string",
                    -- The Length is set to 6 just avoid too short length, it may repeat
                    minLength = 6,
                    default = "abcdefghijklmnopqrstuvwxyzABCDEFGHIGKLMNOPQRSTUVWXYZ0123456789"
                }
            },
            default = {}
        },
        nanoid = {
            type = "object",
            properties = {
                length = {
                    type = "integer",
                    minimum = 6,
                    default = 21
                },
                char_set = {
                    type = "string",
                    minLength = 6,
                    default = "abcdefghijklmnopqrstuvwxyzABCDEFGHIGKLMNOPQRSTUVWXYZ0123456789_-"
                }
            },
            default = {}
        }
    }
}

local _M = {
    version = 0.1,
    priority = 12015,
    name = plugin_name,
    schema = schema
}

function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end

-- generate range_id
local function get_range_id(range_id)
    local res = ffi.new("unsigned char[?]", range_id.length)
    for i = 0, range_id.length - 1 do
        res[i] = str_byte(range_id.char_set, math_random(#range_id.char_set))
    end
    return ffi.string(res, range_id.length)
end

local function get_request_id(conf)
    if conf.algorithm == "uuid" then
        return uuid()
    end

    if conf.algorithm == "nanoid" then
        return nanoid.generate(conf.nanoid.length, conf.nanoid.char_set)
    end

    if conf.algorithm == "range_id" then
        return get_range_id(conf.range_id)
    end

    return uuid()
end


function _M.rewrite(conf, ctx)
    local headers = ngx.req.get_headers()
    local uuid_val
    if not headers[conf.header_name] then
        uuid_val = get_request_id(conf)
        core.request.set_header(ctx, conf.header_name, uuid_val)
    else
        uuid_val = headers[conf.header_name]
    end

    if conf.include_in_response then
        ctx["request-id-" .. conf.header_name] = uuid_val
    end
end

function _M.header_filter(conf, ctx)
    if not conf.include_in_response then
        return
    end

    local headers = ngx.resp.get_headers()
    if not headers[conf.header_name] then
        core.response.set_header(conf.header_name, ctx["request-id-" .. conf.header_name])
    end
end

return _M
