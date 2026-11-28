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
local ngx_re_match = ngx.re.match
local ngx_header = ngx.header
local req_http_version = ngx.req.http_version
local str_find = string.find
local str_lower = string.lower
local str_sub = string.sub
local ipairs = ipairs
local tonumber = tonumber
local assert = assert
local type = type
local brotli = require("apisix.utils.brotli")


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


local CODING_ITEM_REGEX =
    [=[^[ \t]*([!#$%&'*+\-.^_`|~0-9A-Za-z]+)[ \t]*(.*)\z]=]
local WEIGHT_REGEX =
    [[^;[ \t]*[qQ]=(0(?:\.[0-9]{0,3})?|1(?:\.0{0,3})?)[ \t]*\z]]


local function parse_accept_encoding_line(line, br_q, wildcard_q)
    local pos = 1
    local len = #line

    while pos <= len do
        local comma = str_find(line, ",", pos, true)
        local item
        if comma then
            item = str_sub(line, pos, comma - 1)
            pos = comma + 1
        else
            item = str_sub(line, pos)
            pos = len + 1
        end

        local captures, err = ngx_re_match(item, CODING_ITEM_REGEX, "sjo")
        if err then
            core.log.error("failed to match accept-encoding item: ", err)
            return 0, 0
        end

        if captures then
            local coding = str_lower(captures[1])
            if coding == "br" or coding == "*" then
                local q = 0
                local rest = captures[2]
                if rest == "" then
                    q = 1
                else
                    local weight, w_err = ngx_re_match(rest, WEIGHT_REGEX, "jo")
                    if w_err then
                        core.log.error("failed to match qvalue: ", w_err)
                        return 0, 0
                    end
                    if weight then
                        q = tonumber(weight[1])
                    end
                end

                if coding == "br" then
                    if br_q ~= 0 then
                        br_q = q
                    end

                elseif wildcard_q ~= 0 then
                    wildcard_q = q
                end
            end
        end
    end

    return br_q, wildcard_q
end


local function check_accept_encoding(ctx)
    local accept_encoding = core.request.headers(ctx)["accept-encoding"]
    -- no Accept-Encoding
    if not accept_encoding then
        return false
    end

    -- single Accept-Encoding
    if accept_encoding == "*" or accept_encoding == "br" then
        return true
    end

    local br_q = nil
    local wildcard_q = nil
    if type(accept_encoding) == "table" then
        for _, line in ipairs(accept_encoding) do
            br_q, wildcard_q = parse_accept_encoding_line(line, br_q,
                                                          wildcard_q)
        end
    else
        br_q, wildcard_q = parse_accept_encoding_line(accept_encoding, nil,
                                                      nil)
    end

    if br_q ~= nil then
        return br_q > 0
    end

    return wildcard_q ~= nil and wildcard_q > 0
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
    local lib = brotli.get()
    if not lib then
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

    local compressor, err = lib.new_encoder({
        mode = conf.mode,
        quality = conf.comp_level,
        -- The previous binding passed zero to libbrotli, which clamped it to 10.
        lgwin = conf.lgwin == 0 and 10 or conf.lgwin,
        lgblock = conf.lgblock,
    })
    if not compressor then
        core.log.error("failed to create brotli compressor: ", err)
        return
    end

    ctx.brotli_matched = true
    ctx.compressor = compressor
    core.response.set_header("Content-Length", nil)
    core.response.set_header("Content-Encoding", "br")
    weak_etag_header()
end


function _M.body_filter(conf, ctx)
    if not ctx.brotli_matched then
        return
    end

    local chunk, eof = ngx.arg[1], ngx.arg[2]
    if type(chunk) == "string" and chunk ~= "" then
        ngx.arg[1] = assert(ctx.compressor:write(chunk))
    end

    if eof then
        -- overwriting the arg[1], results into partial response
        ngx.arg[1] = ngx.arg[1] .. assert(ctx.compressor:finish())
    end
end


return _M
