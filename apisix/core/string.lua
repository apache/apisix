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

--- Wrapped string module.
--
-- @module core.string

local error = error
local type = type
local str_byte = string.byte
local str_find = string.find
local ffi         = require("ffi")
local C           = ffi.C
local ffi_cast    = ffi.cast
local ngx         = ngx
local ngx_decode_args  = ngx.decode_args
local ngx_encode_args  = ngx.encode_args


ffi.cdef[[
    int memcmp(const void *s1, const void *s2, size_t n);
]]


local _M = {
    version = 0.1,
}


setmetatable(_M, {__index = string})


-- find a needle from a haystack in the plain text way
-- note: Make sure that the haystack is 'string' type, otherwise an exception will be thrown.
function _M.find(haystack, needle, from)
    return str_find(haystack, needle, from or 1, true)
end

---
--  Tests whether the string s begins with prefix.
--
-- @function core.string.has_prefix
-- @tparam string s The string being tested.
-- @tparam string prefix Specify the prefix.
-- @treturn boolean Test result, true means the string s begins with prefix.
-- @usage
-- local res = core.string.has_prefix("/apisix/admin/routes", "/apisix/") -- true
function _M.has_prefix(s, prefix)
    if type(s) ~= "string" or type(prefix) ~= "string" then
        error("unexpected type: s:" .. type(s) .. ", prefix:" .. type(prefix))
    end
    if #s < #prefix then
        return false
    end
    local rc = C.memcmp(s, prefix, #prefix)
    return rc == 0
end


function _M.has_suffix(s, suffix)
    if type(s) ~= "string" or type(suffix) ~= "string" then
        error("unexpected type: s:" .. type(s) .. ", suffix:" .. type(suffix))
    end
    if #s < #suffix then
        return false
    end
    local rc = C.memcmp(ffi_cast("char *", s) + #s - #suffix, suffix, #suffix)
    return rc == 0
end


function _M.rfind_char(s, ch, idx)
    local b = str_byte(ch)
    for i = idx or #s, 1, -1 do
        if str_byte(s, i, i) == b then
            return i
        end
    end
    return nil
end


-- reduce network consumption by compressing string indentation
-- this method should be used with caution
-- it will remove the spaces at the beginning of each line
-- and remove the spaces after `,` character
function _M.compress_script(s)
    s = ngx.re.gsub(s, [[^\s+]], "", "mjo")
    s = ngx.re.gsub(s, [[,\s+]], ",", "mjo")
    return s
end


---
-- Decodes a URI encoded query-string into a Lua table.
-- All request arguments received will be decoded by default.
--
-- @function core.string.decode_args
-- @tparam string args A URI encoded query-string.
-- @treturn table the value of decoded query-string.
-- @usage
-- local args, err = core.string.decode_args("a=1&b=2") -- {a=1, b=2}
function _M.decode_args(args)
    -- use 0 to avoid truncated result and keep the behavior as the
    -- same as other platforms
    return ngx_decode_args(args, 0)
end


---
-- Encode the Lua table to a query args string according to the URI encoded rules.
--
-- @function core.string.encode_args
-- @tparam table args The query args Lua table.
-- @treturn string the value of query args string.
-- @usage
-- local str = core.string.encode_args({a=1, b=2}) -- "a=1&b=2"
function _M.encode_args(args)
    return ngx_encode_args(args)
end

return _M
