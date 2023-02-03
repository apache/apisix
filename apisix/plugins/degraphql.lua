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

local plugin_name = "degraphql"
local ngx         = ngx
local core        = require("apisix.core")
local plugin      = require("apisix.plugin")

local schema = {
    type = "object",
    properties = {
        endpoint = {
            description = "new uri of graphql for upstream",
            type        = "string",
            minLength   = 1,
            maxLength   = 4096,
        },
        query = {
            description = "the graphql body",
            type        = "string",
        },
    },
    anyOf = {
        { required = { "endpoint" } },
        { required = { "query" } }
    }
}


local _M = {
    version = 0.1,
    priority = 1,
    name = plugin_name,
    schema = schema,
}


function _M.check_schema(conf, schema_type)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    if conf.endpoint then
        ok, err = core.schema.valid(conf.endpoint)
        if not ok then
            return false, err
        end
    end

    if conf.query then
        ok, err = core.schema.valid(conf.query)
        if not ok then
            return false, err
        end
    end

    return true, nil
end

local function generate_req_body(conf, ctx)
    local data, err = core.json.encode(conf.query)
    if err then
        core.log.error("generate_req_body: ", err)
    end

    local args = ngx.req.get_uri_args()
    local resloved_var = core.utils.resolve_var(conf.query, args)
    core.log.warn("generate_req_body resloved_var: ", core.json.encode(resloved_var))

    return resloved_var, nil
end

function _M.rewrite(conf, ctx)
    local body, err = core.request.get_body()
    if body then
        return 400, "User input invalid: should pass body"
    end
    if err then
        core.log.error("failed to get body: ", err)
        return 500, "Internal error: failed to get body"
    end

    local req, err = generate_req_body(conf, ctx)
    if err then
        core.log.error("generate request body failed: ", err)
        return 400, "User input invalid: generate request body"
    end
    ngx.req.set_body_data(req)
    ngx.req.set_method(ngx.HTTP_POST)
    ngx.req.set_uri(conf.endpoint)
end

return _M
