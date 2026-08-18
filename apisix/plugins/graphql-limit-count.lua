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
local config_local    = require("apisix.core.config_local")
local gql_cost        = require("apisix.plugins.graphql-limit-count.cost")
local introspection   = require("apisix.plugins.graphql-limit-count.introspection")
local decorations     = require("apisix.plugins.graphql-limit-count.decorations")
local gq_parse        = require("graphql").parse
local limit_count_ver = require("resty.limit.count")._VERSION

local type    = type
local pairs   = pairs
local ipairs  = ipairs
local pcall   = pcall
local max     = math.max
local ceil    = math.ceil
local tonumber = tonumber

local GRAPHQL_DEFAULT_MAX_SIZE = 1048576
local QUERY_COST_HEADER = "X-Graphql-Query-Cost"

local plugin_name = "graphql-limit-count"

-- The plugin reuses the whole limit-count configuration surface and adds the cost
-- model on top of it. limit_count.schema is shared with limit-count,
-- limit-count-advanced and ai-rate-limiting, so it must not be mutated in place.
local schema = core.table.deepcopy(limit_count.schema)

schema.properties.cost_strategy = {
    type = "string",
    enum = {"depth", "complexity", "node_quantifier"},
    -- "depth" is what this plugin has always done; keeping it as the default means
    -- an existing configuration keeps its current cost after the upgrade.
    default = "depth",
}
schema.properties.max_cost = {
    type = "number",
    minimum = 0,
    default = 0,
    description = "reject with 403 above this cost, 0 disables the check",
}
schema.properties.score_factor = {
    type = "number",
    exclusiveMinimum = 0,
    default = 1,
    description = "scaling applied to the raw cost before the quota is charged",
}
schema.properties.resolve_variables = {
    type = "boolean",
    -- On by default: with it off, moving `first: 10000` to `first: $n` makes the
    -- same request cost a fraction of what the literal costs, which is a bypass
    -- of max_cost and of the quota. Turn it off only to reproduce an engine that
    -- ignores variables.
    default = true,
    description = "resolve GraphQL variables and schema argument defaults when " ..
                  "computing the cost, instead of treating them as absent",
}
schema.properties.introspection_endpoint = {
    type = "string",
    pattern = "^https?://",
    description = "explicit schema introspection endpoint, derived from the " ..
                  "upstream when unset",
}
schema.properties.pass_all_downstream_headers = {type = "boolean", default = false}

local _M = {
    version = 0.1,
    priority = 1004,
    name = plugin_name,
    schema = schema,
    -- limit-count owns it; exposing it here is what makes the X-RateLimit-* header
    -- renaming reachable for this plugin, since rate_limit() already looks the
    -- metadata up under this plugin's name
    metadata_schema = limit_count.metadata_schema,
}


function _M.destroy()
    introspection.flush()
end


function _M.check_schema(conf, schema_type)
    -- limit-count owns the count/time_window/rules/group semantics and produces
    -- the field-specific error messages this plugin has always returned. It also
    -- owns the metadata schema, which renames the X-RateLimit-* headers.
    local ok, err = limit_count.check_schema(conf, schema_type)
    if not ok then
        return false, err
    end

    -- plugin metadata is a different document; the cost fields do not apply to it
    if schema_type == core.schema.TYPE_METADATA then
        return true
    end

    ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    return true
end


local GRAPHQL_REQ_QUERY          = "query"
local GRAPHQL_REQ_VARIABLES      = "variables"
local GRAPHQL_REQ_OPERATION_NAME = "operationName"
local GRAPHQL_REQ_MIME_JSON      = "application/json"
local GRAPHQL_REQ_MIME_GQL       = "application/graphql"


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
        local content_type = core.request.header(ctx, "Content-Type") or ""

        if core.string.has_prefix(content_type, GRAPHQL_REQ_MIME_JSON) then
            local res, err = core.json.decode(body)
            if not res then
                return false, "invalid graphql request, " .. err
            end

            if not res[GRAPHQL_REQ_QUERY] then
                return false, "invalid graphql request, json body[" ..
                                GRAPHQL_REQ_QUERY .. "] is nil"
            end

            local variables = res[GRAPHQL_REQ_VARIABLES]
            if type(variables) ~= "table" then
                variables = nil
            end

            local operation_name = res[GRAPHQL_REQ_OPERATION_NAME]
            if type(operation_name) ~= "string" then
                operation_name = nil
            end

            return true, res[GRAPHQL_REQ_QUERY], variables, operation_name
        end

        if core.string.has_prefix(content_type, GRAPHQL_REQ_MIME_GQL) then
            return true, body
        end

        return false, "invalid graphql request, error content-type: " .. content_type
    end
}


-- Returns the maximum selection nesting depth of the GraphQL query AST.
-- Fragment spreads are expanded in place using the provided fragment map;
-- inline fragments are treated as transparent wrappers over their selections.
-- visited tracks the current recursion path: a spread back onto it is a
-- fragment cycle (invalid GraphQL), flagged via cycle.found so the caller can
-- reject the request instead of trusting a traversal-order-dependent depth.
-- memo caches each fragment's resolved depth so a fragment is measured once,
-- keeping the traversal linear in the document size.
local function node_depth(node, fragments, visited, memo, cycle)
    if type(node) ~= "table" then
        return 0
    end

    if node.kind == "fragmentSpread" then
        local name = node.name and node.name.value
        if not name then
            return 0
        end
        if visited[name] then
            cycle.found = true
            return 0
        end
        local cached = memo[name]
        if cached then
            return cached
        end
        local frag = fragments[name]
        if not frag or not frag.selectionSet then
            return 0
        end
        visited[name] = true
        local depth = node_depth(frag.selectionSet.selections, fragments, visited, memo, cycle)
        visited[name] = nil
        memo[name] = depth
        return depth
    end

    if node.kind == "inlineFragment" then
        if not node.selectionSet then
            return 0
        end
        return node_depth(node.selectionSet.selections, fragments, visited, memo, cycle)
    end

    local depth = 0
    for k, v in pairs(node) do
        local child
        if k == "selections" then
            child = 1 + node_depth(v, fragments, visited, memo, cycle)
        else
            child = node_depth(v, fragments, visited, memo, cycle)
        end
        depth = max(depth, child)
    end

    return depth
end


-- Returns the depth, or nil plus the log line and the client message when the
-- document is not valid GraphQL to begin with.
local function query_depth(operations, fragments)
    local depth = 0
    local memo = {}
    local cycle = {found = false}
    for _, op in ipairs(operations) do
        depth = max(depth, node_depth(op, fragments, {}, memo, cycle))
    end

    if cycle.found then
        return nil, "invalid graphql request: fragment spreads form a cycle",
               "Invalid graphql request: fragment spreads must not form cycles"
    end

    depth = max(depth, 1)
    core.log.info("graphql node depth: ", depth)
    return depth
end


-- Returns the raw cost of the query, or nil plus an error message.
local function raw_query_cost(conf, ctx, operations, fragments, variables)
    if conf.cost_strategy == "depth" then
        return query_depth(operations, fragments)
    end

    -- Decorations are owned by the service; a route that is not bound to one has
    -- no place to hang them, so the cost model simply does not apply there.
    local service_decorations
    if ctx.service_id then
        service_decorations = decorations.get(ctx.service_id)
    else
        -- info, not warn: this is on the request path, and the effect is already
        -- visible on every response through X-Graphql-Query-Cost
        core.log.info("the route is not bound to a service, so it has no graphql ",
                      "cost decorations; the query cost degenerates to the node count")
    end

    local schema_index
    if service_decorations then
        local err
        schema_index, err = introspection.get(conf, ctx)
        if not schema_index then
            return nil, err
        end
    end

    return gql_cost.query_cost(conf.cost_strategy, operations, fragments, {
        decorations  = service_decorations,
        schema       = schema_index,
        variables    = conf.resolve_variables and variables or nil,
        use_defaults = conf.resolve_variables,
    })
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

    local max_size = GRAPHQL_DEFAULT_MAX_SIZE
    local local_conf = config_local.local_conf()
    if local_conf then
        local size = core.table.try_read_attr(local_conf, "graphql", "max_size")
        if size then
            local size_num = tonumber(size)
            if size_num and size_num > 0 then
                max_size = size_num
            end
        end
    end

    local body, err = fetch_graphql_body[method](ctx, max_size)
    if not body then
        core.log.error(err)
        return 400, {message = "Invalid graphql request: can't get graphql request body"}
    end

    local is_graphql_req, query_or_err, variables, operation_name =
            check_graphql_request[method](ctx, body)
    if not is_graphql_req then
        core.log.error(query_or_err)
        return 400, {message = query_or_err}
    end

    local ok, res = pcall(gq_parse, query_or_err)
    if not ok then
        core.log.error("failed to parse graphql: ", res)
        return 400, {message = "Invalid graphql request: failed to parse graphql query"}
    end

    -- Split definitions into executable operations and named fragment definitions.
    local fragments = {}
    local operations = {}
    for _, def in ipairs(res.definitions) do
        if def.kind == "fragmentDefinition" then
            fragments[def.name.value] = def
        else
            operations[#operations + 1] = def
        end
    end

    if #operations == 0 then
        core.log.error("failed to parse graphql: empty query")
        return 400, {message = "Invalid graphql request: empty graphql query"}
    end

    -- A document with several operations only executes the one `operationName`
    -- selects, so that is the one to charge for. Without it the request is not a
    -- valid multi operation request at all; the whole document is then costed and
    -- the most expensive operation charged, which cannot under charge whichever
    -- one the upstream ends up running.
    if operation_name and #operations > 1 then
        for _, op in ipairs(operations) do
            if op.name and op.name.value == operation_name then
                operations = {op}
                break
            end
        end
    end

    local raw_cost, client_msg
    raw_cost, err, client_msg = raw_query_cost(conf, ctx, operations, fragments, variables)
    if not raw_cost then
        -- a malformed document reports its own message; anything else is the
        -- introspection failing
        core.log.error(client_msg and err
                       or "failed to compute the graphql query cost: " .. err)
        return 400, {message = client_msg
                               or "Invalid graphql request: failed to introspect the "
                                  .. "upstream graphql schema"}
    end

    -- The +0.01 floor makes a query whose nodes are all undecorated still cost 1.
    -- "depth" is never 0 and has always charged exactly the depth, so it is left
    -- alone: with the default score_factor of 1 the cost is unchanged.
    if conf.cost_strategy ~= "depth" then
        raw_cost = raw_cost + 0.01
    end

    -- ceil keeps the value an integer, which the Redis backend requires anyway
    local cost = max(ceil(raw_cost * (conf.score_factor or 1)), 1)
    core.log.info("graphql query cost: ", cost)

    if conf.show_limit_quota_header then
        core.response.set_header(QUERY_COST_HEADER, cost)
    end

    local code, msg = limit_count.rate_limit(conf, ctx, plugin_name, cost)
    -- A counter backend failure is reported as-is rather than masked by 403, but
    -- it has to be told apart from a rejection: limit-count returns a literal 500
    -- for the former and conf.rejected_code for the latter, and rejected_code
    -- defaults to 503 -- so testing `code >= 500` would have let the default
    -- configuration answer 503 where the max_cost rejection should answer 403.
    if code == 500 and conf.rejected_code ~= 500 then
        return code, msg
    end

    -- The quota is charged before max_cost is enforced, and 403 wins over the
    -- rate limit rejection: an over-sized query is billed even when it is refused.
    local max_cost = conf.max_cost or 0
    if max_cost > 0 and cost > max_cost then
        return 403, {message = "Invalid graphql request: query cost " .. cost ..
                               " exceeds max_cost " .. max_cost}
    end

    return code, msg
end


return _M
