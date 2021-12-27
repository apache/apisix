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
local plugin_name = "mocking"

local schema = {
    type = "object",
    properties = {
        response_schema = { type = "object" }
    },
    required = { "response_schema" }
}

local _M = {
    version = 0.1,
    priority = 9900,
    name = plugin_name,
    schema = schema,
}

function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    if conf.response_schema then
        ok, err = core.schema.valid(conf.response_schema)
        if not ok then
            return false, err
        end
    end

    return true, nil
end

function _M.rewrite(conf)
    if conf.response_schema then
        local output = genObject(conf.response_schema)
        ngx.header["Content-Type"] = "application/json"
        return 200, core.utils.resolve_var(core.json.encode(output))
    end
end

function genObject(property)
    local output = {}
    if property.properties == nil then
        return output
    end
    for k, v in pairs(property.properties) do
        if v.type == "array" then
            output[k] = genArray(v)
        elseif v.type == "object" then
            output[k] = genObject(v)
        else
            output[k] = genBase(v)
        end
    end
    return output
end

function genArray(property)
    local output = {}
    if property.items == nil then
        return nil
    end
    local v = property.items
    local n = math.random(1, 3)
    for i = 1, n do
        if type == "array" then
            table.insert(output, genArray(v))
        elseif type == "object" then
            table.insert(output, genObject(v))
        else
            table.insert(output, genBase(v))
        end
    end
    return output
end

function genBase(property)
    local type = property.type
    local example = property.example
    if type == "string" then
        return genString(example)
    elseif type == "number" then
        return genNumber(example)
    elseif type == "integer" then
        return genInteger(example)
    elseif type == "boolean" then
        return genBoolean(example)
    end
    return nil
end

function genString(example)
    if example ~= nil and type(example) == "string" then
        return example
    end
    local t = {
        "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
        "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
        "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
    }
    local n = math.random(1, 10)
    local s = ""
    for i = 1, n do
        s = s .. t[math.random(#t)]
    end ;
    return s
end

function genNumber(example)
    if example ~= nil and type(example) == "number" then
        return example
    end
    return math.random() * 10000
end

function genInteger(example)
    if example ~= nil and type(example) == "number" then
        return math.floor(example)
    end
    return math.random(1, 10000)
end

function genBoolean(example)
    if example ~= nil and type(example) == "boolean" then
        return example
    end
    local r = math.random(0, 2)
    if r == 0 then
        return false
    end
    return true
end

return _M







