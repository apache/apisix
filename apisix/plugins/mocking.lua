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
local xml2lua = require("xml2lua")

local json = core.json
local math = math
local ngx = ngx
local ngx_re = ngx.re
local pairs = pairs
local string = string
local table = table
local type = type

local support_content_type = {
    ["application/xml"] = true,
    ["application/json"] = true,
    ["text/plain"] = true,
    ["text/html"] = true,
    ["text/xml"] = true
}

local schema = {
    type = "object",
    properties = {
        -- specify response delay time,default 0ms
        delay = { type = "integer", default = 0 },
        -- specify response status,default 200
        response_status = { type = "integer", default = 200, minimum = 100 },
        -- specify response content type, support application/xml, text/plain
        -- and application/json, default application/json
        content_type = { type = "string", default = "application/json;charset=utf8" },
        -- specify response body.
        response_example = { type = "string" },
        -- specify response json schema, if response_example is not nil, this conf will be ignore.
        -- generate random response by json schema.
        response_schema = { type = "object" },
        with_mock_header = { type = "boolean", default = true }
    },
    anyOf = {
        { required = { "response_example" } },
        { required = { "response_schema" } }
    }
}

local _M = {
    version = 0.1,
    priority = 10900,
    name = "mocking",
    schema = schema,
}

local function parse_content_type(content_type)
    if not content_type then
        return ""
    end
    local m = ngx_re.match(content_type, "([ -~]*);([ -~]*)", "jo")
    if m and #m == 2 then
        return m[1], m[2]
    end
    return content_type
end


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    local typ = parse_content_type(conf.content_type)
    if not support_content_type[typ] then
        return false, "unsupported content type!"
    end
    return true
end


local function gen_string(example)
    if example and type(example) == "string" then
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
    if example and type(example) == "number" then
        return example
    end
    return math.random() * 10000
end


local function gen_integer(example)
    if example and type(example) == "number" then
        return math.floor(example)
    end
    return math.random(1, 10000)
end


local function gen_boolean(example)
    if example and type(example) == "boolean" then
        return example
    end
    local r = math.random(0, 1)
    if r == 0 then
        return false
    end
    return true
end


local gen_array, gen_object, gen_by_property

function gen_array(property)
    local output = {}
    if property.items == nil then
        return nil
    end
    local v = property.items
    local n = math.random(1, 3)
    for i = 1, n do
        table.insert(output, gen_by_property(v))
    end
    return output
end


function gen_object(property)
    local output = {}
    if not property.properties then
        return output
    end
    for k, v in pairs(property.properties) do
        output[k] = gen_by_property(v)
    end
    return output
end


function gen_by_property(property)
    local typ = string.lower(property.type)
    local example = property.example

    if typ == "array" then
        return gen_array(property)
    end

    if typ == "object" then
        return gen_object(property)
    end

    if typ == "string" then
        return gen_string(example)
    end

    if typ == "number" then
        return gen_number(example)
    end

    if typ == "integer" then
        return gen_integer(example)
    end

    if typ == "boolean" then
        return gen_boolean(example)
    end

    return nil
end


function _M.access(conf, ctx)
    local response_content = ""

    if conf.response_example then
        response_content = conf.response_example
    else
        local output = gen_object(conf.response_schema)
        local typ = parse_content_type(conf.content_type)
        if typ == "application/xml" or typ == "text/xml" then
            response_content = xml2lua.toXml(output, "data")

        elseif typ == "application/json" or typ == "text/plain" then
            response_content = json.encode(output)

        else
            core.log.error("json schema body only support xml and json content type")
        end
    end

    ngx.header["Content-Type"] = conf.content_type
    if conf.with_mock_header then
        ngx.header["x-mock-by"] = "APISIX/" .. core.version.VERSION
    end

    if conf.delay > 0 then
        ngx.sleep(conf.delay)
    end
    return conf.response_status, core.utils.resolve_var(response_content, ctx.var)
end

return _M
