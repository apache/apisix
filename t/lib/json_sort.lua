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

local type = type
local concat = table.concat
local tostring = tostring
local ngx_null = ngx.null
local gsub = string.gsub
local sort = table.sort
local pairs = pairs
local ipairs = ipairs


local _M = {}


local meta_chars = {
    ["\t"] = "\\t",
    ["\\"] = "\\\\",
    ['"'] = '\\"',
    ["\r"] = "\\r",
    ["\n"] = "\\n",
}


local function encode_str(s)
    return gsub(s, '["\\\r\n\t]', meta_chars)
end


local function is_arr(t)
    local exp = 1
    for k, _ in pairs(t) do
        if k ~= exp then
            return nil
        end
        exp = exp + 1
    end
    return exp - 1
end


local encode
function encode (v)
    if v == nil or v == ngx_null then
        return "null"
    end

    local typ = type(v)
    if typ == 'string' then
        return '"' .. encode_str(v) .. '"'
    end

    if typ == 'number' or typ == 'boolean' then
        return tostring(v)
    end

    if typ == 'table' then
        local n = is_arr(v)
        if n then
            local bits = {}
            for i, elem in ipairs(v) do
                bits[i] = encode(elem)
            end
            return "[" .. concat(bits, ",") .. "]"
        end

        local keys = {}
        local i = 0
        for key, _ in pairs(v) do
            i = i + 1
            keys[i] = key
        end
        sort(keys)

        local bits = {}
        i = 0
        for _, key in ipairs(keys) do
            i = i + 1
            bits[i] = encode(key) .. ":" .. encode(v[key])
        end
        return "{" .. concat(bits, ",") .. "}"
    end

    return '"<' .. typ .. '>"'
end
_M.encode = encode


return _M
