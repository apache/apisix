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

--- Unicode hardening helpers shared by ai-security plugins.
-- Strips zero-width and bidirectional-override code points (common PII-regex
-- bypass vectors) and exposes an NFKC normalization hook when the linked
-- luautf8 build supports it.

local core    = require("apisix.core")
local ngx_re  = require("ngx.re")
local pcall   = pcall
local require = require

local _M = {}


-- Best-effort NFKC binding. luautf8 0.2.x exposes utf8.normalize_nfkc;
-- older builds omit it, in which case we degrade to a no-op and rely on
-- the strip steps to close the common bypasses.
local utf8_lib
do
    local ok, mod = pcall(require, "lua-utf8")
    if ok then
        utf8_lib = mod
    end
end

local function nfkc(str)
    if not utf8_lib then
        return str
    end
    local fn = utf8_lib.normalize_nfkc or utf8_lib.nfkc
    if not fn then
        return str
    end
    local ok, out = pcall(fn, str)
    if not ok then
        core.log.warn("NFKC normalization failed, leaving input unchanged: ", out)
        return str
    end
    return out
end


-- Code points we strip when strip_zero_width is on.
-- U+200B ZWSP, U+200C ZWNJ, U+200D ZWJ, U+2060 WORD JOINER, U+FEFF BOM.
local ZERO_WIDTH_RE = "[\\x{200B}\\x{200C}\\x{200D}\\x{2060}\\x{FEFF}]"

-- Bidi override range: U+202A-E (LRE/RLE/PDF/LRO/RLO) and U+2066-9
-- (LRI/RLI/FSI/PDI). These are the characters used in the Trojan Source
-- class of attacks; legitimate text almost never contains them.
local BIDI_RE = "[\\x{202A}-\\x{202E}\\x{2066}-\\x{2069}]"


--- Apply the configured hardening steps to a string.
-- @param s string Input
-- @param opts table {strip_zero_width, strip_bidi, normalize}
--   normalize: "nfkc" or "none"
-- @return string
function _M.harden(s, opts)
    if type(s) ~= "string" or s == "" then
        return s
    end
    opts = opts or {}

    -- Order: normalize first so canonical equivalents collapse,
    -- then strip, so bypasses built on visually-invisible codepoints fail.
    if opts.normalize == "nfkc" then
        s = nfkc(s)
    end

    if opts.strip_zero_width then
        local out, _, err = ngx_re.gsub(s, ZERO_WIDTH_RE, "", "jou")
        if out then
            s = out
        elseif err then
            core.log.warn("zero-width strip failed: ", err)
        end
    end

    if opts.strip_bidi then
        local out, _, err = ngx_re.gsub(s, BIDI_RE, "", "jou")
        if out then
            s = out
        elseif err then
            core.log.warn("bidi strip failed: ", err)
        end
    end

    return s
end


return _M
