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
local parser  = require("xml2lua").parser
local re_gsub = ngx.re.gsub
local table_to_xml  = require("xml2lua").toXml

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
    return 200, core.json.encode(convert_handler.root)
end

local function json2xml(table_data)
    local xmlStr = table_to_xml(core.json.decode(table_data))
    local res, _, err = re_gsub(xmlStr, "\\s+", "", "jo")
    if not res then
        return 400, err
    end
    return 200, res
end

local _switch_anonymous = {
    ["json"] = function(content_type, req_body, to)
        if core.string.find(content_type, "application/json", 1, true) == nil then
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
        if core.string.find(content_type, "text/xml", 1, true) == nil then
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

return _M
