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
local core       = require("apisix.core")
local str_sub    = string.sub
local str_rep    = string.rep
local table_concat = table.concat

local _M = {}

local MAX_PRETTY_SIZE = 256 * 1024
local INDENT_UNIT = "  "


-- cjson has no pretty printer, so re-flow its compact output instead of
-- re-implementing value encoding and string escaping. Matches
-- JSON.stringify(value, null, 2): two-space indent, ": " after keys, and
-- empty containers kept on one line.
--
-- Object key order still comes from the Lua table, so the result is not
-- byte-identical to JSON.stringify for nested upstream payloads. That is a
-- known, semantically irrelevant difference.
function _M.encode(value)
    local compact, err = core.json.encode(value)
    if not compact then
        return nil, err
    end

    -- Indenting builds one table entry per character, so a large payload would
    -- cost many times its own size in memory. Past this point the compact form
    -- is returned as it is: it says the same thing, with no blank space.
    if #compact > MAX_PRETTY_SIZE then
        return compact
    end

    local out = {}
    local indent = 0
    local in_string = false
    local escaped = false
    local index = 1
    local length = #compact

    while index <= length do
        local char = str_sub(compact, index, index)

        if in_string then
            out[#out + 1] = char
            if escaped then
                escaped = false
            elseif char == "\\" then
                escaped = true
            elseif char == '"' then
                in_string = false
            end

        elseif char == '"' then
            in_string = true
            out[#out + 1] = char

        elseif char == "{" or char == "[" then
            local next_char = str_sub(compact, index + 1, index + 1)
            if (char == "{" and next_char == "}") or (char == "[" and next_char == "]") then
                out[#out + 1] = char .. next_char
                index = index + 1
            else
                indent = indent + 1
                out[#out + 1] = char .. "\n" .. str_rep(INDENT_UNIT, indent)
            end

        elseif char == "}" or char == "]" then
            indent = indent - 1
            out[#out + 1] = "\n" .. str_rep(INDENT_UNIT, indent) .. char

        elseif char == "," then
            out[#out + 1] = ",\n" .. str_rep(INDENT_UNIT, indent)

        elseif char == ":" then
            out[#out + 1] = ": "

        else
            out[#out + 1] = char
        end

        index = index + 1
    end

    return table_concat(out)
end


return _M
