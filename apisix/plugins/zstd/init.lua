--
-- Licensed to the Apache Software Foundation (ASF) under one
-- or more contributor license agreements.  See the NOTICE file
-- distributed with this work for additional information
-- regarding copyright ownership.  The ASF licenses this file
-- to you under the Apache License, Version 2.0 (the
-- "License"); you may not use this file except in compliance
-- with the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing,
-- software distributed under the License is distributed on an
-- "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
-- KIND, either express or implied.  See the License for the
-- specific language governing permissions and limitations
-- under the License.
--
local core = require("apisix.core")
local ngx = ngx
local ngx_re_gmatch = ngx.re.gmatch
local ngx_header = ngx.header
local req_http_version = ngx.req.http_version
local str_sub = string.sub
local ipairs = ipairs
local tonumber = tonumber
local type = type
local is_loaded, zstd = pcall(require, "apisix.plugins.zstd.binding")


local schema = {
    type = "object",
    properties = {
        types = {
            anyOf = {
                {
                    type = "array",
                    minItems = 1,
                    items = {
                        type = "string",
                        minLength = 1,
                    },
                },
                {
                    enum = {"*"}
                }
            },
            default = {"text/html"}
        },
        min_length = {
            type = "integer",
            minimum = 1,
            default = 20,
        },
        comp_level = {
            type = "integer",
            minimum = 1,
            maximum = 19,
            default = 3,
            -- levels above 19 ("ultra") enlarge the decoder window beyond the
            -- 8 MB that RFC 9659 requires HTTP decoders to support
        },
        http_version = {
            enum = {1.1, 1.0},
            default = 1.1,
        },
        vary = {
            type = "boolean",
        }
    },
}


local _M = {
    version = 0.1,
    priority = 994,
    name = "zstd",
    schema = schema,
}


function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end


local function create_zstd_compressor(comp_level)
    return zstd.compressor:new({level = comp_level})
end


local function check_accept_encoding(ctx)
    local accept_encoding = core.request.header(ctx, "Accept-Encoding")
    -- no Accept-Encoding
    if not accept_encoding then
        return false
    end

    -- single Accept-Encoding
    if accept_encoding == "*" or accept_encoding == "zstd" then
        return true
    end

    -- multi Accept-Encoding
    local iterator, err = ngx_re_gmatch(accept_encoding,
                                        [[([a-z\*]+)(;q=)?([0-9.]*)?]], "jo")
    if not iterator then
        core.log.error("gmatch failed, error: ", err)
        return false
    end

    local captures
    while true do
        captures, err = iterator()
        if not captures then
            break
        end
        if err then
            core.log.error("iterator failed, error: ", err)
            return false
        end
        if (captures[1] == "zstd" or captures[1] == "*") and
           (not captures[2] or captures[3] ~= "0") then
            return true
        end
    end

    return false
end


local function weak_etag_header()
    local etag = ngx_header["Etag"]

    if not etag then
        return
    end

    local regex = [[^(W/)?"([^"]*)"$]]
    local matched, err = ngx.re.match(etag, regex, "jo")
    if err then
        core.log.error("failed to match etag: ", err)
    end
    if not matched then
        -- non-standard etag (not quoted) or a match failure; it cannot be
        -- weakened, so drop it
        core.response.set_header("Etag", nil)
        return
    end

    if not matched[1] then
        -- strong etag, downgrade it
        core.response.set_header("Etag", [[W/"]] .. matched[2] .. [["]])
    else
        -- weak etag, keep it
        return
    end
end


function _M.header_filter(conf, ctx)
    if not is_loaded then
        core.log.error("please check the zstd library")
        return
    end

    local allow_encoding = check_accept_encoding(ctx)
    if not allow_encoding then
        return
    end

    local content_encoded = ngx_header["Content-Encoding"]
    if content_encoded then
        -- Don't compress if Content-Encoding is present in upstream data
        return
    end

    local types = conf.types
    local content_type = ngx_header["Content-Type"]
    if not content_type then
        -- Like Nginx, don't compress if Content-Type is missing
        return
    end

    if type(types) == "table" then
        local matched = false
        local from = core.string.find(content_type, ";")
        if from then
            content_type = str_sub(content_type, 1, from - 1)
        end

        for _, ty in ipairs(types) do
            if content_type == ty then
                matched = true
                break
            end
        end

        if not matched then
            return
        end
    end

    local content_length = tonumber(ngx_header["Content-Length"])
    if content_length then
        local min_length = conf.min_length
        if content_length < min_length then
            return
        end
        -- Like Nginx, don't check min_length if Content-Length is missing
    end

    local http_version = req_http_version()
    if http_version < conf.http_version then
        return
    end

    if conf.vary then
        core.response.add_header("Vary", "Accept-Encoding")
    end

    local compressor = create_zstd_compressor(conf.comp_level)
    if not compressor then
        core.log.error("failed to create zstd compressor")
        return
    end

    ctx.zstd_matched = true
    ctx.compressor = compressor
    core.response.set_header("Content-Length", nil)
    core.response.set_header("Content-Encoding", "zstd")
    weak_etag_header()
end


function _M.body_filter(conf, ctx)
    if not ctx.zstd_matched then
        return
    end

    local chunk, eof = ngx.arg[1], ngx.arg[2]
    if type(chunk) == "string" and chunk ~= "" then
        local encode_chunk = ctx.compressor:compress(chunk)
        ngx.arg[1] = encode_chunk .. ctx.compressor:flush()
    end

    if eof then
        -- overwriting the arg[1], results into partial response
        ngx.arg[1] = ngx.arg[1] .. ctx.compressor:finish()
    end
end


return _M
