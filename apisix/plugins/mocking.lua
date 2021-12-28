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

    return true, nil
end

function _M.access(conf)
    local output = gen_object(conf.response_schema)
    ngx.header["Content-Type"] = "application/json"
    return 200, core.utils.resolve_var(core.json.encode(output))
end

function gen_object(property)
    local output = {}
    if property.properties == nil then
        return output
    end
    for k, v in pairs(property.properties) do
        local type = string.lower(v.type)
        if type == "array" then
            output[k] = gen_array(v)
        elseif type == "object" then
            output[k] = gen_object(v)
        else
            output[k] = get_base(v)
        end
    end
    return output
end

function gen_array(property)
    local output = {}
    if property.items == nil then
        return nil
    end
    local v = property.items
    local n = math.random(1, 3)
    local type = string.lower(v.type)
    for i = 1, n do
        if type == "array" then
            table.insert(output, gen_array(v))
        elseif type == "object" then
            table.insert(output, gen_object(v))
        else
            table.insert(output, get_base(v))
        end
    end
    return output
end

function get_base(property)
    local type = string.lower(property.type)
    local example = property.example
    if type == "string" then
        return gen_string(example)
    elseif type == "number" then
        return gen_number(example)
    elseif type == "integer" then
        return gen_integer(example)
    elseif type == "boolean" then
        return gen_boolean(example)
    end
    return nil
end

function gen_string(example)
    if example ~= nil and type(example) == "string" then
        return example
    end
    local n = math.random(1, 10)
    local list = {}
    for i = 1, n do
        table.insert(list, string.char(math.random(97, 122)))
    end
    return table.concat(list)
end

function gen_number(example)
    if example ~= nil and type(example) == "number" then
        return example
    end
    return math.random() * 10000
end

function gen_integer(example)
    if example ~= nil and type(example) == "number" then
        return math.floor(example)
    end
    return math.random(1, 10000)
end

function gen_boolean(example)
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







