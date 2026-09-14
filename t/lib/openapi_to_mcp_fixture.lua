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


-- content handler for `location /`
function _M.serve()
    local uri = ngx.var.uri
    ngx.header["Content-Type"] = "application/json"

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
