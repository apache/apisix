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
local xmlhandler        = require("xmlhandler.tree")
local template          = require("resty.template")
local ngx               = ngx
local decode_base64     = ngx.decode_base64
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
    anyOf = {
        {required = {"request"}},
        {required = {"response"}},
        {required = {"request", "response"}},
    },
}


local _M = {
    version  = 0.1,
    priority = 1080,
    name     = "body-transformer",
    schema   = schema,
}


local function escape_xml(s)
    return s:gsub("&", "&amp;")
        :gsub("<", "&lt;")
        :gsub(">", "&gt;")
        :gsub("'", "&apos;")
        :gsub('"', "&quot;")
end


local function escape_json(s)
    return core.json.encode(s)
end


local function remove_namespace(tbl)
    for k, v in pairs(tbl) do
        if type(k) == "string" then
            local newk = k:match(".*:(.*)")
            if newk then
                tbl[newk] = v
                tbl[k] = nil
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
        local handler = xmlhandler:new()
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
    local out = {_body = body}
    if body then
        local err
        local format = conf[typ].input_format
        if format then
            out, err = decoders[format](body)
            if not out then
                err = str_format("%s body decode: %s", typ, err)
                core.log.error(err, ", body=", body)
                return nil, 400, err
            end
        end
    end

    local text = conf[typ].template
    text = decode_base64(text) or text
    local ok, render = pcall(template.compile, text)
    if not ok then
        local err = render
        err = str_format("%s template compile: %s", typ, err)
        core.log.error(err)
        return nil, 503, err
    end

    out._ctx = ctx
    out._escape_xml = escape_xml
    out._escape_json = escape_json
    local ok, render_out = pcall(render, out)
    if not ok then
        local err = str_format("%s template rendering: %s", typ, render_out)
        core.log.error(err)
        return nil, 503, err
    end

    core.log.info(typ, " body transform output=", render_out)
    return render_out
end


local function set_input_format(conf, typ, ct)
    if conf[typ].input_format == nil and ct then
        if ct:find("text/xml") then
            conf[typ].input_format = "xml"
        elseif ct:find("application/json") then
            conf[typ].input_format = "json"
        end
    end
end


function _M.rewrite(conf, ctx)
    if conf.request then
        conf = core.table.deepcopy(conf)
        ctx.body_transformer_conf = conf
        local body = core.request.get_body()
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
        if not ctx.body_transformer_conf then
            conf = core.table.deepcopy(conf)
            ctx.body_transformer_conf = conf
        end
        set_input_format(conf, "response", ngx.header.content_type)
        core.response.clear_header_as_body_modified()
    end
end


function _M.body_filter(_, ctx)
    local conf = ctx.body_transformer_conf
    if conf.response then
        local body = core.response.hold_body_chunk(ctx)
        if ngx.arg[2] == false and not body then
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
