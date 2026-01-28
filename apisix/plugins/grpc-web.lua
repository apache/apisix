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

local ngx               = ngx
local ngx_arg           = ngx.arg
local core              = require("apisix.core")
local req_set_uri       = ngx.req.set_uri
local req_set_body_data = ngx.req.set_body_data
local decode_base64     = ngx.decode_base64
local encode_base64     = ngx.encode_base64
local bit               = require("bit")
local string            = string


local ALLOW_METHOD_OPTIONS = "OPTIONS"
local ALLOW_METHOD_POST = "POST"
local CONTENT_ENCODING_BASE64 = "base64"
local CONTENT_ENCODING_BINARY = "binary"
local DEFAULT_CORS_ALLOW_ORIGIN = "*"
local DEFAULT_CORS_ALLOW_METHODS = ALLOW_METHOD_POST
local DEFAULT_CORS_ALLOW_HEADERS = "content-type,x-grpc-web,x-user-agent"
local DEFAULT_CORS_EXPOSE_HEADERS = "grpc-message,grpc-status"
local DEFAULT_PROXY_CONTENT_TYPE = "application/grpc"


local plugin_name = "grpc-web"

local schema = {
    type = "object",
    properties = {
        cors_allow_headers = {
            description =
            "multiple header use ',' to split. default: content-type,x-grpc-web,x-user-agent.",
            type = "string",
            default = DEFAULT_CORS_ALLOW_HEADERS
        }
    }
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

local function exit(ctx, status)
    ctx.grpc_web_skip_body_filter = true
    return status
end

--- Build gRPC-Web trailer chunk
-- grpc-web trailer format reference:
--     envoyproxy/envoy/source/extensions/filters/http/grpc_web/grpc_web_filter.cc
--
-- Format for grpc-web trailer
--     1 byte: 0x80
--     4 bytes: length of the trailer
--     n bytes: trailer
-- It using upstream_trailer_* variables from nginx, it is available since NGINX version 1.13.10
-- https://nginx.org/en/docs/http/ngx_http_upstream_module.html#var_upstream_trailer_
--
-- @param grpc_status number grpc status code
-- @param grpc_message string grpc message
-- @return string grpc-web trailer chunk in raw string
local build_trailer = function (grpc_status, grpc_message)
    local status_str = "grpc-status:" .. grpc_status
    local status_msg = "grpc-message:" .. ( grpc_message or "")
    local grpc_web_trailer = status_str .. "\r\n" .. status_msg .. "\r\n"
    local len = #grpc_web_trailer

    -- 1 byte: 0x80
    local trailer_buf = string.char(0x80)
    -- 4 bytes: length of the trailer
    trailer_buf = trailer_buf .. string.char(
        bit.band(bit.rshift(len, 24), 0xff),
        bit.band(bit.rshift(len, 16), 0xff),
        bit.band(bit.rshift(len, 8), 0xff),
        bit.band(len, 0xff)
    )
    -- n bytes: trailer
    trailer_buf = trailer_buf .. grpc_web_trailer

    return trailer_buf
end

function _M.access(conf, ctx)
    -- set context variable mime
    -- When processing non gRPC Web requests, `mime` can be obtained in the context
    -- and set to the `Content-Type` of the response
    ctx.grpc_web_mime = core.request.header(ctx, "Content-Type")

    local method = core.request.get_method()
    if method == ALLOW_METHOD_OPTIONS then
        return exit(ctx, 204)
    end

    if method ~= ALLOW_METHOD_POST then
        -- https://github.com/grpc/grpc-web/blob/master/doc/browser-features.md#cors-support
        core.log.error("request method: `", method, "` invalid")
        return exit(ctx, 405)
    end

    local encoding = grpc_web_content_encoding[ctx.grpc_web_mime]
    if not encoding then
        core.log.error("request Content-Type: `", ctx.grpc_web_mime, "` invalid")
        return exit(ctx, 400)
    end

    -- set context variable encoding method
    ctx.grpc_web_encoding = encoding

    local path = ctx.curr_req_matched[":ext"]
    if path and path ~= "" then
        if path:byte(1) ~= core.string.byte("/") then
            path = "/" .. path
        end
        req_set_uri(path)
    end

    -- set grpc body
    local body, err = core.request.get_body()
    if err or not body then
        core.log.error("failed to read request body, err: ", err)
        return exit(ctx, 400)
    end

    if encoding == CONTENT_ENCODING_BASE64 then
        body = decode_base64(body)
        if not body then
            core.log.error("failed to decode request body")
            return exit(ctx, 400)
        end
    end

    -- set grpc content-type
    core.request.set_header(ctx, "Content-Type", DEFAULT_PROXY_CONTENT_TYPE)
    -- set grpc body
    req_set_body_data(body)
end

function _M.header_filter(conf, ctx)
    local method = core.request.get_method()
    if method == ALLOW_METHOD_OPTIONS then
        core.response.set_header("Access-Control-Allow-Methods", DEFAULT_CORS_ALLOW_METHODS)
        core.response.set_header("Access-Control-Allow-Headers", conf.cors_allow_headers)
    end

    if not ctx.cors_allow_origins then
        core.response.set_header("Access-Control-Allow-Origin", DEFAULT_CORS_ALLOW_ORIGIN)
    end
    core.response.set_header("Access-Control-Expose-Headers", DEFAULT_CORS_EXPOSE_HEADERS)

    if not ctx.grpc_web_skip_body_filter then
        core.response.set_header("Content-Type", ctx.grpc_web_mime)
        core.response.set_header("Content-Length", nil)
    end

    -- Set gRPC Web metadata sent flag
    -- The RPC calls on the gRPC service may fail without returning any data,
    -- i.e., send `grpc-status` and `grpc-message`, but send an empty response body
    -- In this case, the grpc metadata metadata (usually sent in the trailer) may
    -- be sent with the HTTP/2 header.
    --
    -- 1. Normal gRPC (HTTP/2):
    --
    --   => HEADER frame => DATA frame => HEADER (trailer) frame with end stream flag => [END]
    --
    --   There will be a DATA frame between the HEADER frame (which contains the HTTP/2
    --   pseudo-header such as :status) and the trailer header frame, which is sent in two
    --   separate frames, and which was handled correctly by the previous implementation.
    --
    -- 2. Exception gRPC (HTTP/2 or gRPC-Web over HTTP1):
    --
    --   => HEADER(+trailers) frame (with end header flag and end stream flag) => [END]
    --
    --   If the gRPC call chooses not to return any data but instead returns a gRPC error
    --   directly (via grpc-status), the DATA frame will be omitted and the gRPC metadata field,
    --   which is normally located in the trailer, will be sent as a header along with the
    --   regular HTTP/2 header.
    --   For APISIX, its nginx http grpc module will handle HTTP/2 details on gRPC connections,
    --   and for this exception case, the gRPC metadata will no longer be treated as a trailer
    --   but rather as a general HTTP header. So it will no longer be readable as
    --   an `upstream_trailer_grpc_status` variable, but only with `sent_http_grpc_status`.
    --
    -- We must deal with the second exception carefully. As required by the gRPC Web message frame:
    --
    --   Trailers-only responses: no change to the gRPC protocol spec. Trailers may be
    --   sent together with response headers, with no message in the body.
    --   ref: https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-WEB.md
    --
    -- Therefore, when this situation exists, we confirm here that the `grpc-status` response header
    -- has been sent and set a flag.
    -- In subsequent body_filter phases, if it finds that this flag has been set, it skips attempts
    -- to append additional trailer encoding to the end of the response body.
    -- This is compliant, i.e., this is a trailers-only response, send the gRPC metadata contained
    -- in the trailers in the HTTP response header and ensure that an empty response body is
    -- sent (no trailers block in the end of response body).
    ctx.grpc_web_metadata_sent = ctx.var.sent_http_grpc_status ~= nil
end

function _M.body_filter(conf, ctx)
    if ctx.grpc_web_skip_body_filter then
        return
    end

    -- If the MIME extension type description of the gRPC-Web standard is not obtained,
    -- indicating that the request is not based on the gRPC Web specification,
    -- the processing of the request body will be ignored
    -- https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-WEB.md
    -- https://github.com/grpc/grpc-web/blob/master/doc/browser-features.md#cors-support
    if not ctx.grpc_web_mime then
        return
    end

    if ctx.grpc_web_encoding == CONTENT_ENCODING_BASE64 then
        local chunk = ngx_arg[1]
        chunk = encode_base64(chunk)
        ngx_arg[1] = chunk
    end

    if ngx_arg[2] then -- if eof
        -- If the gRPC metadata has already been sent through the response header,
        -- the subsequent logic is skipped and no trailers chunk is appended.
        if ctx.grpc_web_metadata_sent then
            return
        end

        local status = ctx.var.upstream_trailer_grpc_status
        local message = ctx.var.upstream_trailer_grpc_message

        -- When the response body completes and still does not receive the grpc status
        local resp_ok = status ~= nil and status ~= ""
        local trailer_buf = build_trailer(
            resp_ok and status  or 2,
            resp_ok and message or "upstream grpc status not received"
        )
        if ctx.grpc_web_encoding == CONTENT_ENCODING_BASE64 then
            trailer_buf = encode_base64(trailer_buf)
        end

        ngx_arg[1] = ngx_arg[1] .. trailer_buf
    end
end

return _M
