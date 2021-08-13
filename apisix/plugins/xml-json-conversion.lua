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

local ngx     = ngx
local core    = require("apisix.core")
local xml2lua = require("xml2lua")
local handler = require("xmlhandler.tree")
local cjson   = require('cjson.safe')
local assert  = assert
local io      = io
local string  = string

local metadata_schema = {
    type = "object",
    properties = {},
    additionalProperties = false,
}

local schema = {
    type = "object",
    properties = {},
    additionalProperties = false,
}

local plugin_name = "xml-json-conversion"

local _M = {
    version = 0.1,
    priority = 90,
    name = plugin_name,
    schema = schema,
    metadata_schema = metadata_schema,
}

function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end

local function getFile(file_name)
    local f = assert(io.open(file_name, 'r'))
    local string = f:read("*all")
    f:close()
    return string
end

local function xml2json(xml_data)
    local convertHandler = handler:new()
    local parser = xml2lua.parser(convertHandler)
    parser:parse(xml_data)
    return 200, cjson.encode(convertHandler.root)
end

local function json2xml(table_data)
    return 200, xml2lua.toXml(cjson.decode(table_data))
end

function _M.access(conf, ctx)
    core.log.warn("\n||||||| ctx ,", core.json.encode(ctx, true))
    core.log.warn("\n||||||| conf ,", core.json.encode(conf, true))

    local request_header = ngx.req.get_headers()
    ngx.req.read_body()
    local request_body = ngx.req.get_body_data()
    if nil == request_body then
        local file_name = ngx.req.get_body_file()
        if file_name then
            request_body = getFile(file_name)
        end
    end

    core.log.warn("------- request_body : ", request_body)
    if request_header["Content-Type"] == "application/json" then
        if string.find(request_header["Accept"], "text/xml") == nil then
            return 401, {message = "Operation not supported"}
        end
        return json2xml(request_body)
    elseif request_header["Content-Type"] == "text/xml" then
        if string.find(request_header["Accept"], "application/json") == nil then
            return 401, {message = "Operation not supported"}
        end
        return xml2json(request_body)
    else
        return 401, {message = "Operation not supported"}
    end
end

local function get_json()
    local request_header = ngx.req.get_headers()
    ngx.req.read_body()
    local request_body = ngx.req.get_body_data()
    if nil == request_body then
        local file_name = ngx.req.get_body_file()
        if file_name then
            request_body = getFile(file_name)
        end
    end
    if nil == request_body then
        return 401, {message = "Invalid request body"}
    end

    if request_header["Content-Type"] == "application/json" then
        if string.find(request_header["Accept"], "text/xml") == nil then
            return 401, {message = "Operation not supported"}
        end
        return json2xml(request_body)
    elseif request_header["Content-Type"] == "text/xml" then
        if string.find(request_header["Accept"], "application/json") == nil then
            return 401, {message = "Operation not supported"}
        end
        return xml2json(request_body)
    else
        return 401, {message = "Operation not supported"}
    end
end

function _M.api()
    return {
        {
            methods = {"GET"},
            uri = "/v1/plugin/xml-json-conversion",
            handler = get_json,
        }
    }
end

--function _M.control_api()
--    return {
--        {
--            methods = {"GET"},
--            uris ={"/v1/plugin/xml-json-conversion"},
--            handler = get_json,
--        }
--    }
--end

return _M
