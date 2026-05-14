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
local limit_count     = require("apisix.plugins.limit-count.init")
local core            = require("apisix.core")
local gq_parse        = require("graphql").parse
local limit_count_ver = require("resty.limit.count")._VERSION

local type = type
local pairs = pairs
local pcall = pcall

local plugin_name = "graphql-limit-count"
local _M = {
    version = 0.1,
    priority = 1004,
    name = plugin_name,
    schema = limit_count.schema,
}


function _M.check_schema(conf)
    return limit_count.check_schema(conf)
end


local GRAPHQL_REQ_QUERY     = "query"
local GRAPHQL_REQ_MIME_JSON = "application/json"
local GRAPHQL_REQ_MIME_GQL  = "application/graphql"


local fetch_graphql_body = {
    ["POST"] = function(ctx, max_size)
        local body, err = core.request.get_body(max_size, ctx)
        if not body then
            return nil, "failed to read graphql data, " .. (err or "request body has zero size")
        end

        return body
    end
}


local check_graphql_request = {
    ["POST"] = function(ctx, body)
        local content_type = core.request.header(ctx, "Content-Type")
        if content_type == GRAPHQL_REQ_MIME_JSON then
            local res, err = core.json.decode(body)
            if not res then
                return false, "invalid graphql request, " .. err
            end

            if not res[GRAPHQL_REQ_QUERY] then
                return false, "invalid graphql request, json body[" ..
                                GRAPHQL_REQ_QUERY .. "] is nil"
            end

            return true, res[GRAPHQL_REQ_QUERY]
        end

        if content_type == GRAPHQL_REQ_MIME_GQL then
            if not core.string.find(body, GRAPHQL_REQ_QUERY) then
                return false, "invalid graphql request, can't find '" ..
                            GRAPHQL_REQ_QUERY .. "' in request body"
            end
            return true, body
        end

        return false, "invalid graphql request, error content-type: " .. (content_type or "")
    end
}


-- Finds the depth of the graphql query from the given AST table.
local function node_depth(t)
    local depth = 0
    if type(t) ~= "table" then
        return depth
    end

    for k, v in pairs(t) do
        if k == "selections" then
            depth = depth + 1
        end
        depth = depth + node_depth(v)
    end

    return depth
end


function _M.access(conf, ctx)
    if limit_count_ver < '1.0.0' then
        core.log.error("need to build APISIX-Base to support GraphQL limit count")
        return 501
    end

    local method = core.request.get_method()
    if method ~= "POST" then
        return 405
    end

    local body, err = fetch_graphql_body[method](ctx)
    if not body then
        core.log.error(err)
        return 400, {message = "Invalid graphql request: cant't get graphql request body"}
    end

    local is_graphql_req, query_or_err = check_graphql_request[method](ctx, body)
    if not is_graphql_req then
        core.log.error(query_or_err)
        return 400, {message = "Invalid graphql request: no query"}
    end

    local ok, res = pcall(gq_parse, query_or_err)
    if not ok then
        core.log.error("failed to parse graphql: ", res, ", body: ", body)
        return 400, {message = "Invalid graphql request: failed to parse graphql query"}
    end

    local n = #res.definitions
    if n == 0 then
        core.log.error("failed to parse graphql: empty query, body: ", body)
        return 400, {message = "Invalid graphql request: empty graphql query"}
    end

    local depth = node_depth(res)
    core.log.info("graphql node depth: ", depth)

    return limit_count.rate_limit(conf, ctx, plugin_name, depth)
end


return _M
