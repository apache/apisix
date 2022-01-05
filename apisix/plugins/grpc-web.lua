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

local ngx = ngx
local ngx_arg = ngx.arg
local core = require("apisix.core")
local req_set_uri = ngx.req.set_uri
local decode_base64 = ngx.decode_base64
local encode_base64 = ngx.encode_base64


local ALLOW_METHOD_OPTIONS = "OPTIONS"
local ALLOW_METHOD_POST = "POST"
local CONTENT_ENCODING_BASE64 = "base64"
local CONTENT_ENCODING_BINARY = "binary"
local DEFAULT_CORS_CONTENT_TYPE = "application/grpc-web-text+proto"
local DEFAULT_CORS_ALLOW_ORIGIN = "*"
local DEFAULT_CORS_ALLOW_METHODS = ALLOW_METHOD_POST
local DEFAULT_CORS_ALLOW_HEADERS = "content-type,x-grpc-web,x-user-agent"
local DEFAULT_PROXY_CONTENT_TYPE = "application/grpc"


local plugin_name = "grpc-web"

local schema = {
    type = "object",
    properties = {},
}

local grpc_web_content_encoding = {
    ["application/grpc-web"] = CONTENT_ENCODING_BINARY,
    ["application/grpc-web-text"] = CONTENT_ENCODING_BASE64,
    ["application/grpc-web+proto"] = CONTENT_ENCODING_BINARY,
    ["application/grpc-web-text+proto"] = CONTENT_ENCODING_BASE64,
}

local _M = {
    version = 0.1,
    priority = 505,
    name = plugin_name,
    schema = schema,
}

function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end

function _M.access(conf, ctx)
    local method = core.request.get_method()
    if method == ALLOW_METHOD_OPTIONS then
        return 204
    end

    if method ~= ALLOW_METHOD_POST then
        -- https://github.com/grpc/grpc-web/blob/master/doc/browser-features.md#cors-support
        core.log.error("request method: `", method, "` invalid")
        return 400
    end

    local mimetype = core.request.header(ctx, "Content-Type")
    local encoding = grpc_web_content_encoding[mimetype]
    if not encoding then
        core.log.error("request Content-Type: `", mimetype, "` invalid")
        return 400
    end

    -- set grpc path
    if not (ctx.curr_req_matched and ctx.curr_req_matched[":ext"]) then
        core.log.error("please use matching pattern for routing URI, for example: /* or /grpc/*")
        return 400
    end

    local path = ctx.curr_req_matched[":ext"]
    if path:byte(1) ~= core.string.byte("/") then
        path = "/" .. path
    end

    req_set_uri(path)

    -- set grpc body
    local body, err = core.request.get_body()
    if err then
        core.log.error("reading body err, ", err)
        return 400
    end

    if body and encoding == CONTENT_ENCODING_BASE64 then
        body = decode_base64(body)
    end

    local ok
    ok, err = core.request.set_raw_body(body)
    if not ok then
        core.log.error("setting body err, ", err)
        return 400
    end

    -- set grpc content-type
    core.request.set_header(ctx, "Content-Type", DEFAULT_PROXY_CONTENT_TYPE)

    -- set context variable
    ctx.grpc_web_mime = mimetype
    ctx.grpc_web_encoding = encoding
end

function _M.header_filter(conf, ctx)
    local method = core.request.get_method()
    if method == ALLOW_METHOD_OPTIONS then
        core.response.set_header("Access-Control-Allow-Methods", DEFAULT_CORS_ALLOW_METHODS)
        core.response.set_header("Access-Control-Allow-Headers", DEFAULT_CORS_ALLOW_HEADERS)
    end
    core.response.set_header("Access-Control-Allow-Origin", DEFAULT_CORS_ALLOW_ORIGIN)
    core.response.set_header("Content-Type", ctx.grpc_web_mime or DEFAULT_CORS_CONTENT_TYPE)
end

function _M.body_filter(conf, ctx)
    -- If the gRPC-Web standard MIME extension type is not obtained or
    -- the `POST` method is not used for interaction according to the gRPC-Web specification,
    -- the request body processing will be ignored
    -- https://github.com/grpc/grpc-web/blob/master/doc/browser-features.md#cors-support
    local method = core.request.get_method()
    if not ctx.grpc_web_mime or method ~= ALLOW_METHOD_POST then
        return
    end

    if ctx.grpc_web_encoding == CONTENT_ENCODING_BASE64 then
        local chunk = ngx_arg[1]
        chunk = encode_base64(chunk)
        ngx_arg[1] = chunk
    end
end

return _M
