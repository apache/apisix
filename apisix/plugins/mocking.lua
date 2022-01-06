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
local xml2lua = require("xml2lua")

local schema = {
    type = "object",
    properties = {
        -- specify response delay time,default 0ms
        delay = { type = "integer" },
        -- specify response status,default 200
        response_status = { type = "integer", default = 200, minimum = 1 },
        -- specify response content type,support application/xml,text/plain and application/json,default application/json
        content_type = { type = "string", default = "application/json" },
        -- specify response body.
        response_example = { type = "string" },
        -- specify response json schema,if response_example is not nil,this conf will be ignore.
        -- generate random response by json schema.
        response_schema = { type = "object" },
    },
    anyOf = {
        { required = { "response_example" } },
        { required = { "response_schema" } }
    }
}

local _M = {
    version = 0.1,
    priority = 9900,
    name = "mocking",
    schema = schema,
}

local function parse_content_type(content_type)
    if not content_type then
        return "", ""
    end
    local sep_idx = string.find(content_type, ";")
    local type, charset
    if sep_idx then
        type = string.sub(content_type, 1, sep_idx - 1)
        charset = string.sub(content_type, sep_idx + 1)
    else
        type = content_type
    end
    return type, charset
end

function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    if conf.content_type == "" then
        conf.content_type = "application/json;charset=utf8"
    end
    local type, _ = parse_content_type(conf.content_type)
    if type ~= "application/xml" and
            type ~= "application/json" and
            type ~= "text/plain" and
            type ~= "text/html" and
            type ~= "text/xml" then
        return false, "unsupported content type!"
    end
    return true
end

local function gen_string(example)
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

local function gen_number(example)
    if example ~= nil and type(example) == "number" then
        return example
    end
    return math.random() * 10000
end

local function gen_integer(example)
    if example ~= nil and type(example) == "number" then
        return math.floor(example)
    end
    return math.random(1, 10000)
end

local function gen_boolean(example)
    if example ~= nil and type(example) == "boolean" then
        return example
    end
    local r = math.random(0, 1)
    if r == 0 then
        return false
    end
    return true
end

local function gen_base(property)
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
            table.insert(output, gen_base(v))
        end
    end
    return output
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
            output[k] = gen_base(v)
        end
    end
    return output
end

function _M.access(conf)
    local response_content = ""

    if conf.response_example then
        response_content = conf.response_example
    else
        local output = gen_object(conf.response_schema)
        local type, _ = parse_content_type(conf.content_type)
        if type == "application/xml" or type == "text/xml" then
            response_content = xml2lua.toXml(output, "data")
        elseif type == "application/json" or type == "text/plain" then
            response_content = core.json.encode(output)
        else
            core.log.error("json schema body only support xml and json content type")
        end
    end

    ngx.header["Content-Type"] = conf.content_type
    if conf.delay > 0 then
        ngx.sleep(conf.delay)
    end
    return conf.response_status, core.utils.resolve_var(response_content)
end

return _M
