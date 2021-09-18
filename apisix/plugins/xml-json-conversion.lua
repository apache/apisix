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

local core    = require("apisix.core")
local handler = require("xmlhandler.tree")
local string  = require("string")
local parser   = require("xml2lua").parser
local table_to_xml  = require("xml2lua").toXml
local json_decode   = require('cjson.safe').decode
local json_encode   = require('cjson.safe').encode


local schema = {
    type = "object",
    properties = {
        from = {
            type = "string",
            enum = {"json", "xml"},
            default = "xml"
        },
        to = {
            type = "string",
            enum = {"json", "xml"},
            default = "json"
        }
    },
    additionalProperties = false,
}

local plugin_name = "xml-json-conversion"

local _M = {
    version = 0.1,
    priority = 9,
    name = plugin_name,
    schema = schema,
}

function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end

local function xml2json(xml_data)
    local convert_handler = handler:new()
    local parser_handler = parser(convert_handler)
    parser_handler:parse(xml_data)
    return 200, json_encode(convert_handler.root)
end

local function json2xml(table_data)
    local xmlStr = table_to_xml(json_decode(table_data))
    xmlStr = string.gsub(xmlStr, "%s+", "")
    return 200, xmlStr
end

local _switch_anonymous = {
    ["json"] = function(content_type, req_body, to)
        if string.find(content_type, "application/json", 1, true) == nil then
            return 400, {message = "Operation not supported"}
        end

        local data, err = core.json.decode(req_body)
        if not data then
            core.log.error("invalid request body: ", req_body, " err: ", err)
            return 400, {error_msg = "invalid request body: " .. err,
                         req_body = req_body}
        end
        if to == 'xml' then
            return json2xml(req_body)
        else
            return 400, {message = "Operation not supported"}
        end
    end,
    ["xml"] = function(content_type, req_body, to)
        if string.find(content_type, "text/xml", 1, true) == nil then
            return 400, {message = "Operation not supported"}
        end
        if to == 'json' then
            return xml2json(req_body)
        else
            return 400, {message = "Operation not supported"}
        end
    end
}

local function process(from, to)
    local req_body, err = core.request.get_body()
    if err or req_body == nil or req_body == '' then
        core.log.error("failed to read request body: ", err)
        core.response.exit(400, {error_msg = "invalid request body: " .. err})
    end

    if from == to then
        return req_body
    end

    local content_type = core.request.headers()["Content-Type"]
    local _f_anon = _switch_anonymous[from]
    if _f_anon then
        return _f_anon(content_type, req_body, to)
    else
        return 400, {message = "Operation not supported"}
    end
end

function _M.access(conf, ctx)
    local from = conf.from
    local to = conf.to

    return process(from, to)
end

local function conversion()
    local args = core.request.get_uri_args()
    if not args or not args.from or not args.to then
        return core.response.exit(400)
    end

    local from = args.from
    local to = args.to

    return process(from, to)
end

function _M.api()
    return {
        {
            methods = {"GET"},
            uri = "/apisix/plugin/xml-json-conversion",
            handler = conversion,
        }
    }
end

return _M
