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

-- What the openapi-to-mcp suites point the plugin at: the OpenAPI documents
-- under test, served next to the API their tools call.
local core = require("apisix.core")
local t    = require("lib.test_admin").test


local _M = {}


local DOCUMENTS = {
    ["/openapi.json"] = {
        openapi = "3.0.0",
        info = { title = "Demo", version = "1.0.0" },
        paths = { ["/pet/{petId}"] = { get = {
            operationId = "getPet",
            summary = "Get a pet",
            parameters = {
                { name = "petId", ["in"] = "path", required = true,
                  schema = { type = "integer" } },
                { name = "verbose", ["in"] = "query",
                  schema = { type = "boolean", default = true } },
            },
        } } },
    },

    -- one query parameter per OpenAPI serialization style
    ["/styles.json"] = {
        openapi = "3.0.0",
        info = { title = "Styles", version = "1" },
        paths = { ["/s"] = { get = {
            operationId = "styles",
            parameters = {
                { name = "formArr", ["in"] = "query", explode = false,
                  schema = { type = "array", items = { type = "string" } } },
                { name = "spaceArr", ["in"] = "query", style = "spaceDelimited",
                  schema = { type = "array", items = { type = "string" } } },
                { name = "pipeArr", ["in"] = "query", style = "pipeDelimited",
                  schema = { type = "array", items = { type = "string" } } },
                { name = "deep", ["in"] = "query", style = "deepObject", explode = true,
                  schema = { type = "object", properties = { x = { type = "string" } } } },
                { name = "formObj", ["in"] = "query", explode = false,
                  schema = { type = "object", properties = { k = { type = "string" } } } },
            },
        } } },
    },

    -- a tool that declares one header parameter
    ["/headerparam.json"] = {
        openapi = "3.0.0",
        info = { title = "Header", version = "1" },
        paths = { ["/traced"] = { get = {
            operationId = "traced",
            parameters = {
                { name = "X-Trace", ["in"] = "header", schema = { type = "string" } },
                { name = "Authorization", ["in"] = "header", schema = { type = "string" } },
            },
        } } },
    },

    -- parameters declared on the Path Item, one of them overridden
    ["/pathitem.json"] = {
        openapi = "3.0.0",
        info = { title = "Path item", version = "1" },
        paths = { ["/pets/{id}"] = {
            parameters = {
                { name = "id", ["in"] = "path", required = true, schema = { type = "integer" } },
                { name = "verbose", ["in"] = "query", schema = { type = "boolean" } },
            },
            get = {
                operationId = "getPetById",
                parameters = {
                    { name = "verbose", ["in"] = "query", schema = { type = "string" } },
                },
            },
        } },
    },

    -- one operation over the endpoint that answers with a large body
    ["/large.json"] = {
        openapi = "3.0.0",
        info = { title = "Large", version = "1" },
        paths = { ["/large"] = { get = {
            operationId = "getLarge",
            parameters = {
                { name = "size", ["in"] = "query", schema = { type = "integer" } },
            },
        } } },
    },

    -- a request body whose only media type is not JSON
    ["/textbody.json"] = {
        openapi = "3.0.0",
        info = { title = "Text body", version = "1" },
        paths = { ["/notes"] = { post = {
            operationId = "addNote",
            requestBody = { required = true, content = { ["text/plain"] = {
                schema = { type = "string" } } } },
        } } },
    },

    -- query parameters that are an object and an array
    ["/objq.json"] = {
        openapi = "3.0.0",
        info = { title = "Q", version = "1" },
        paths = { ["/q"] = { get = {
            operationId = "objQuery",
            parameters = {
                { name = "filter", ["in"] = "query", schema = {
                    type = "object", properties = { a = { type = "string" } } } },
                { name = "tags", ["in"] = "query", schema = {
                    type = "array", items = { type = "string" } } },
            },
        } } },
    },
}


-- Served from fixed files, so the path order a test sees is the order written
-- in the document rather than whatever order a Lua table encodes in.
local FILES = {
    -- petstore3, the same document oas-validator is tested with
    ["/petstore.json"] = "../spec/spec.json",
    -- `in: body` / `in: formData` and `definitions`; source in
    -- openapi_to_mcp_swagger2_spec.lua
    ["/swagger2.json"] = "openapi_to_mcp_swagger2_spec.json",
}


local function read_body()
    ngx.req.read_body()
    return ngx.req.get_body_data()
end


-- answers with a body of the requested size, for the response size limit
local function large_body()
    local size = tonumber(ngx.var.arg_size) or (2 * 1024 * 1024)
    ngx.header["Content-Type"] = "application/json"
    ngx.print('{"blob":"', string.rep("x", size), '"}')
end


-- content handler for `location /`
function _M.serve()
    local uri = ngx.var.uri
    ngx.header["Content-Type"] = "application/json"

    if uri == "/large" then
        return large_body()
    end

    local doc = DOCUMENTS[uri]
    if doc then
        ngx.say(core.json.encode(doc))
        return
    end

    local file = FILES[uri]
    if file then
        local f = assert(io.open(ngx.config.prefix() .. "../lib/" .. file, "r"))
        ngx.print(f:read("*a"))
        f:close()
        return
    end

    -- anything else is the API a generated tool called: say what it received
    ngx.say(core.json.encode({
        seen_path = ngx.var.request_uri,
        seen_method = ngx.req.get_method(),
        seen_auth = ngx.req.get_headers()["authorization"],
        seen_injected = ngx.req.get_headers()["x-injected"],
        seen_trace = ngx.req.get_headers()["x-trace"],
        seen_forwarded = ngx.req.get_headers()["x-forwarded-for"],
        seen_content_type = ngx.req.get_headers()["content-type"],
        seen_body = ngx.req.get_method() ~= "GET" and read_body() or nil,
    }))
end


-- PUT one openapi-to-mcp route per { id, uri, conf[, plugins] } entry.
-- Prints and returns false on the first failure, true when all are in.
function _M.put_routes(routes)
    for _, route in ipairs(routes) do
        local id, uri, conf, plugins = route[1], route[2], route[3], route[4] or {}
        plugins["openapi-to-mcp"] = conf
        local code, body = t("/apisix/admin/routes/" .. id, ngx.HTTP_PUT,
            core.json.encode({
                uri = uri,
                plugins = plugins,
                upstream = { nodes = { ["127.0.0.1:1980"] = 1 }, type = "roundrobin" },
            }))
        if code >= 300 then
            ngx.say("route ", id, ": ", body)
            return false
        end
    end
    return true
end


return _M
