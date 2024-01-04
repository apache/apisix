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
local core = require("apisix.core")
local ngx = ngx
local ngx_re_gmatch = ngx.re.gmatch
local ngx_header = ngx.header
local req_http_version = ngx.req.http_version
local str_sub = string.sub
local ipairs = ipairs
local tonumber = tonumber
local type = type
local is_loaded, brotli = pcall(require, "brotli")


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
        mode = {
            type = "integer",
            minimum = 0,
            maximum = 2,
            default = 0,
            -- 0: MODE_GENERIC (default),
            -- 1: MODE_TEXT (for UTF-8 format text input)
            -- 2: MODE_FONT (for WOFF 2.0)
        },
        comp_level = {
            type = "integer",
            minimum = 0,
            maximum = 11,
            default = 6,
            -- follow the default value from ngx_brotli brotli_comp_level
        },
        lgwin = {
            type = "integer",
            default = 19,
            -- follow the default value from ngx_brotli brotli_window
            enum = {0,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24},
        },
        lgblock = {
            type = "integer",
            default = 0,
            enum = {0,16,17,18,19,20,21,22,23,24},
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
    priority = 996,
    name = "brotli",
    schema = schema,
}


function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end


local function create_brotli_compressor(mode, comp_level, lgwin, lgblock)
    local options = {
        mode = mode,
        quality = comp_level,
        lgwin = lgwin,
        lgblock = lgblock,
    }
    return brotli.compressor:new(options)
end


local function check_accept_encoding(ctx)
    local accept_encoding = core.request.header(ctx, "Accept-Encoding")
    -- no Accept-Encoding
    if not accept_encoding then
        return false
    end

    -- single Accept-Encoding
    if accept_encoding == "*" or accept_encoding == "br" then
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
        if (captures[1] == "br" or captures[1] == "*") and
           (not captures[2] or captures[3] ~= "0") then
            return true
        end
    end

    return false
end


function _M.header_filter(conf, ctx)
    if not is_loaded then
        core.log.error("please check the brotli library")
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

    local compressor = create_brotli_compressor(conf.mode, conf.comp_level,
                                                conf.lgwin, conf.lgblock)
    if not compressor then
        core.log.error("failed to create brotli compressor")
        return
    end

    ctx.brotli_matched = true
    ctx.compressor = compressor
    core.response.clear_header_as_body_modified()
    core.response.add_header("Content-Encoding", "br")
end


function _M.body_filter(conf, ctx)
    if not ctx.brotli_matched then
        return
    end

    local chunk, eof = ngx.arg[1], ngx.arg[2]
    if type(chunk) == "string" and chunk ~= "" then
        local encode_chunk = ctx.compressor:compress(chunk)
        ngx.arg[1] = encode_chunk .. ctx.compressor:flush()
    end

    if eof then
        ngx.arg[1] = ctx.compressor:finish()
    end
end


return _M
