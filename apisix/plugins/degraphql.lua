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
local gq_parse = require("graphql").parse
local req_set_body_data = ngx.req.set_body_data
local ipairs = ipairs
local pcall = pcall
local type = type


local schema = {
    type = "object",
    properties = {
        query = {
            type = "string",
            minLength = 1,
            maxLength = 1024,
        },
        variables = {
            type = "array",
            items = {
                type = "string"
            },
            minItems = 1,
        },
        operation_name = {
            type = "string",
            minLength = 1,
            maxLength = 1024
        },
    },
    required = {"query"},
}

local plugin_name = "degraphql"

local _M = {
    version = 0.1,
    priority = 509,
    name = plugin_name,
    schema = schema,
}


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    local ok, res = pcall(gq_parse, conf.query)
    if not ok then
        return false, "failed to parse query: " .. res
    end

    if #res.definitions > 1 and not conf.operation_name then
        return false, "operation_name is required if multiple operations are present in the query"
    end
    return true
end


local function fetch_post_variables(conf)
    local req_body, err = core.request.get_body()
    if err ~= nil then
        core.log.error("failed to get request body: ", err)
        return nil, 503
    end

    if not req_body then
        core.log.error("missing request body")
        return nil, 400
    end

    -- JSON as the default content type
    req_body, err = core.json.decode(req_body)
    if type(req_body) ~= "table" then
        core.log.error("invalid request body can't be decoded: ", err or "bad type")
        return nil, 400
    end

    local variables = {}
    for _, v in ipairs(conf.variables) do
        variables[v] = req_body[v]
    end

    return variables
end


local function fetch_get_variables(conf)
    local args = core.request.get_uri_args()
    local variables = {}
    for _, v in ipairs(conf.variables) do
        variables[v] = args[v]
    end

    return variables
end


function _M.access(conf, ctx)
    local meth = core.request.get_method()
    if meth ~= "POST" and meth ~= "GET" then
        return 405
    end

    local new_body = core.table.new(0, 3)

    if conf.variables then
        local variables, code
        if meth == "POST" then
            variables, code = fetch_post_variables(conf)
        else
            variables, code = fetch_get_variables(conf)
        end

        if not variables then
            return code
        end

        if meth == "POST" then
            new_body["variables"] = variables
        else
            new_body["variables"] = core.json.encode(variables)
        end
    end

    new_body["operationName"] = conf.operation_name
    new_body["query"] = conf.query

    if meth == "POST" then
        if not conf.variables then
            -- the set_body_data requires to read the body first
            core.request.get_body()
        end

        core.request.set_header(ctx, "Content-Type", "application/json")
        req_set_body_data(core.json.encode(new_body))
    else
        core.request.set_uri_args(ctx, new_body)
    end
end


return _M
