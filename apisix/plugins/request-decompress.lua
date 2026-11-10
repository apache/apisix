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

local core    = require("apisix.core")
local gzip    = require("apisix.utils.gzip")
local ipairs  = ipairs
local type    = type
local ngx_req = ngx.req
local str_gmatch = string.gmatch
local str_lower  = string.lower
local tab_concat = table.concat

local plugin_name = "request-decompress"

local IDENTITY_ENCODING = "identity"
-- windowBits 15 emits a zlib stream, which is the deflate coding
local DEFLATE_OPTS = {windowBits = 15}

-- gzip and deflate are both zlib streams, inflate_gzip auto-detects the header
local SUPPORTED_ENCODINGS = {
    gzip = true,
    deflate = true,
}
-- advertised in Accept-Encoding when a request is rejected over its encoding
local SUPPORTED_CONTENT_ENCODINGS = "gzip, deflate"

local BODY_ERRORS = {
    unsupported_encoding = {status = 415},
    decompress_failed = {status = 400, message = "failed to decompress request body"},
    too_large = {status = 413, message = "request body is too large"},
}

local schema = {
    type = "object",
    properties = {
        max_req_body_size = {
            type = "integer",
            minimum = 1,
            default = 1048576,
            description = "maximum size in bytes of the decompressed request body; "
                       .. "a body inflating beyond it is rejected with 413",
        },
        forward_compressed = {
            type = "boolean",
            default = false,
            description = "forward a compressed body upstream instead of the decompressed "
                       .. "one; the plugins on the route still read the decompressed body",
        },
    },
}


local _M = {
    version = 0.1,
    priority = 2850,
    name = plugin_name,
    schema = schema,
    -- a route that configures the plugin owns the request, so the instance from
    -- a global rule is dropped and the body is handled exactly once
    run_policy = "prefer_route",
}


function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end


local function collect_codings(value, codings)
    for coding in str_gmatch(value, "[^,%s]+") do
        codings[#codings + 1] = str_lower(coding)
    end
end


-- codings are returned in the order they were applied to the body. A repeated
-- Content-Encoding header carries as many codings as a single comma-joined one.
local function get_content_encodings(ctx)
    -- read from the header table, since core.request.header collapses a
    -- repeated header to its first line
    local value = core.request.headers(ctx)["content-encoding"]
    if not value then
        return nil
    end

    local codings = {}
    if type(value) == "table" then
        for _, v in ipairs(value) do
            collect_codings(v, codings)
        end
    else
        collect_codings(value, codings)
    end

    return codings
end


-- an unclassified cause is a read failure rather than anything the client did
local function body_error(err, err_kind)
    core.log.error("failed reading request body, err: ", err)

    local known = err_kind and BODY_ERRORS[err_kind]
    if not known then
        return 500, {message = "error reading the request body. err: " .. err}
    end

    if err_kind == "unsupported_encoding" then
        core.response.set_header("Accept-Encoding", SUPPORTED_CONTENT_ENCODINGS)
    end

    return known.status, {message = known.message or err}
end


-- inflates the body in the reverse order the codings were applied, bounding
-- their total output by max_size. The third return value names the failure.
local function decompress(body, max_size, codings)
    for i = #codings, 1, -1 do
        if codings[i] ~= IDENTITY_ENCODING then
            local plain, err, exceeded = gzip.inflate_gzip(body, nil, nil, max_size)
            if not plain then
                return nil, err, exceeded and "too_large" or "decompress_failed"
            end
            body = plain
        end
    end

    return body
end


-- re-applies the codings in the order the client applied them. Returns the
-- compressed body and the codings that were actually applied.
local function compress(body, codings)
    local applied = {}

    for _, coding in ipairs(codings) do
        if coding ~= IDENTITY_ENCODING then
            local opts = coding == "deflate" and DEFLATE_OPTS or nil
            local compressed, err = gzip.deflate_gzip(body, nil, opts)
            if not compressed then
                return nil, nil, err
            end
            body = compressed
            applied[#applied + 1] = coding
        end
    end

    return body, applied
end


-- Content-Length is rewritten along with the body
local function clear_content_length_cache(ctx)
    local var_cache = ctx.var and ctx.var._cache
    if var_cache then
        var_cache.http_content_length = nil
    end
end


function _M.rewrite(conf, ctx)
    -- an uncompressed request is left untouched, its body is never read
    local codings = get_content_encodings(ctx)
    if not codings then
        return
    end

    -- a coding we cannot inflate is rejected before the body is read
    for _, coding in ipairs(codings) do
        if coding ~= IDENTITY_ENCODING and not SUPPORTED_ENCODINGS[coding] then
            return body_error("unsupported content encoding: " .. coding,
                              "unsupported_encoding")
        end
    end

    local original, err, err_kind = core.request.get_body(conf.max_req_body_size, ctx)
    if err then
        return body_error(err, err_kind)
    end

    local body
    if original then
        body, err, err_kind = decompress(original, conf.max_req_body_size, codings)
        if not body then
            return body_error(err, err_kind)
        end
        ngx_req.set_body_data(body)
    end

    core.request.set_header(ctx, "Content-Encoding", nil)

    clear_content_length_cache(ctx)

    if conf.forward_compressed and original then
        ctx.request_decompress = {
            codings = codings,
            original = original,
            plain = body,
        }
    end
end


function _M.before_proxy(_, ctx)
    local state = ctx.request_decompress
    if not state then
        return
    end
    -- the state is an instruction to carry out once, not a description
    ctx.request_decompress = nil

    -- read through core so a body another plugin moved to a file is found too
    local current, err = core.request.get_body(nil, ctx)
    if err then
        core.log.error("failed reading request body, err: ", err)
        return 500, {message = "error reading the request body. err: " .. err}
    end
    -- a body a plugin emptied is not a body that could not be read
    current = current or ""

    -- nothing rewrote the body, so the bytes as they arrived still apply
    if current == state.plain then
        ngx_req.set_body_data(state.original)
        -- the codings as the client applied them, which a repeated
        -- Content-Encoding header makes longer than any single header line
        core.request.set_header(ctx, "Content-Encoding", tab_concat(state.codings, ", "))
        clear_content_length_cache(ctx)
        return
    end

    local body, applied, compress_err = compress(current, state.codings)
    if not body then
        core.log.error("failed to compress request body, err: ", compress_err)
        return 500, {message = "failed to compress request body"}
    end

    ngx_req.set_body_data(body)
    clear_content_length_cache(ctx)
    -- the header names the codings applied here, which is shorter than the list
    -- the client sent when one of them was identity
    local header = #applied > 0 and tab_concat(applied, ", ") or nil
    core.request.set_header(ctx, "Content-Encoding", header)
end


return _M
