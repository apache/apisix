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
local core              = require("apisix.core")
local xml2lua           = require("xml2lua")
local handler           = require("xmlhandler.tree")
local template          = require("resty.template")
local ngx               = ngx
local req_set_body_data = ngx.req.set_body_data
local str_format        = string.format
local type              = type
local pcall             = pcall
local pairs             = pairs


local transform_schema = {
    type = "object",
    properties = {
        input_format = { type = "string", enum = {"xml", "json"} },
        template = { type = "string" },
    },
    required = {"template"},
}

local schema = {
    type = "object",
    properties = {
        request = transform_schema,
        response = transform_schema,
    },
}


local _M = {
    version  = 0.1,
    priority = 1080,
    name     = "body-transformer",
    schema   = schema,
}


-- luacheck: ignore
function string.escape_xml(s)
    return s:gsub("&", "&amp;")
        :gsub("<", "&lt;")
        :gsub(">", "&gt;")
        :gsub("'", "&apos;")
        :gsub('"', "&quot;")
end


-- luacheck: ignore
function string.escape_json(s)
    return core.json.encode(s)
end


local function remove_namespace(tbl)
    for k, v in pairs(tbl) do
        if type(k) == "string" then
            k = k:match(".*:(.*)")
            if k then
                tbl[k] = v
            end
            if type(v) == "table" then
                remove_namespace(v)
            end
        end
    end
    return tbl
end


local decoders = {
    xml = function(data)
        local handler = handler:new()
        local parser = xml2lua.parser(handler)
        local ok, err = pcall(parser.parse, parser, data)
        if ok then
            return remove_namespace(handler.root)
        else
            return nil, err
        end
    end,
    json = function(data)
        return core.json.decode(data)
    end,
}


function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end


local function transform(conf, body, typ, ctx)
    local out, err = decoders[conf[typ].input_format](body)
    if not out then
        err = str_format("%s body decode: %s", typ, err)
        core.log.error(err, ", body=", body)
        return nil, 400, err
    end

    local ok, render = pcall(template.compile, conf[typ].template)
    if not ok then
        local err = render
        err = str_format("%s template compile: %s", typ, err)
        core.log.error(err)
        return nil, 500, err
    end

    out._ctx = ctx
    ok, out = pcall(render, out)
    if not ok then
        err = str_format("%s template rendering: %s", typ, out)
        core.log.error(err)
        return nil, 500, err
    end

    return out
end


local function set_input_format(conf, typ, ct)
    if conf.input_format == nil and ct then
        if ct:find("text/xml") then
            conf[typ].input_format = "xml"
        elseif ct:find("application/json") then
            conf[typ].input_format = "json"
        end
    end
end


function _M.rewrite(conf, ctx)
    if conf.request then
        local body = core.request.get_body()
        if not body then
            return
        end

        set_input_format(conf, "request", ctx.var.http_content_type)
        local out, status, err = transform(conf, body, "request", ctx)
        if not out then
            return status, { message = err }
        end
        req_set_body_data(out)
    end
end


function _M.header_filter(conf, ctx)
    if conf.response then
        set_input_format(conf, "response", ngx.header.content_type)
        core.response.clear_header_as_body_modified()
    end
end


function _M.body_filter(conf, ctx)
    if conf.response then
        local body = core.response.hold_body_chunk(ctx)
        if not body then
            return
        end

        local out = transform(conf, body, "response", ctx)
        if not out then
            core.log.error("failed to transform response body: ", body)
            return
        end

        ngx.arg[1] = out
    end
end


return _M