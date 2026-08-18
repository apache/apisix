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
--
-- GraphQL query cost engine.
--
-- Implements the `complexity` and `node_quantifier` cost strategies on the AST
-- produced by the `graphql` rock.
--
-- Cost decorations are keyed by `<GraphQL type>.<field>`, so matching a query
-- field against a decoration requires the upstream schema: the walker carries a
-- type cursor that descends alongside the selection tree. Without a schema no
-- decoration can match and every node falls back to its default weights.
--
local core   = require("apisix.core")

local ipairs     = ipairs
local type       = type
local tonumber   = tonumber
local math_max   = math.max
local str_gmatch = string.gmatch
local tab_sort   = table.sort

local _M = {}

-- the fields a decoration contributes; everything else on the value is metadata
local WEIGHT_KEYS = {"add_value", "mul_value", "add_arguments", "mul_arguments"}

local EMPTY_INDEX = {flat = {}, root = {children = {}}, deep = false}

-- How many selections the walk may expand. A real query is in the hundreds; a
-- document that spreads fragments into an exponential DAG reaches this in
-- milliseconds and is rejected instead of costed.
local EXPANSION_BUDGET = 100000


local function field_name(node)
    return node.name and node.name.value
end


-- A field_path is a chain of GraphQL name tokens. `Person.name` weights the field
-- `name` wherever it is selected on a `Person`; `Query.products.nodes.reviews`
-- pins one specific chain of fields. Both live in the same trie, one node per
-- token, so matching is a walk rather than a string compare.
local function insert_path(root, deco)
    local node = root
    local depth = 0

    for token in str_gmatch(deco.field_path, "[^.]+") do
        depth = depth + 1
        local children = node.children
        if not children then
            children = {}
            node.children = children
        end

        local child = children[token]
        if not child then
            child = {}
            children[token] = child
        end
        node = child
    end

    -- a single token names a type, not a field, and weights nothing
    if depth < 2 then
        return 0
    end

    node.decoration = deco
    node.depth = depth
    return depth
end


---
-- Compiles a service's decorations into the index `query_cost` consumes. Built
-- once per configuration version, not per request.
-- @tparam table list decoration values, each carrying a `field_path`
function _M.build_index(list)
    local index = {flat = {}, root = {children = {}}, deep = false}

    for _, deco in ipairs(list or {}) do
        if type(deco.field_path) == "string" then
            local depth = insert_path(index.root, deco)
            if depth == 2 then
                index.flat[deco.field_path] = deco
            elseif depth > 2 then
                index.deep = true
            end
        end
    end

    return index
end


-- Advances the candidate paths for one field: the ones inherited from the parent
-- move on by this field's name, and a fresh candidate is seeded from the root by
-- this field's own type. Seeding by type is what lets a two segment path match at
-- any depth, while carrying the parent's candidates forward keeps a longer path
-- pinned to its chain.
local function advance(root, queue, type_name, name)
    local next_queue

    if queue then
        for _, candidate in ipairs(queue) do
            local children = candidate.children
            local child = children and children[name]
            if child then
                next_queue = next_queue or {}
                next_queue[#next_queue + 1] = child
            end
        end
    end

    local seed = type_name and root.children[type_name]
    if seed then
        next_queue = next_queue or {}
        next_queue[#next_queue + 1] = seed
    end

    return next_queue
end


-- Two paths can name the same field: `Product.reviews` and
-- `Query.products.nodes.reviews` both match one node. They are merged key by key,
-- least specific first, so the longer path wins wherever they disagree. Resolving
-- by path length rather than by storage order keeps the cost a function of the
-- configuration alone.
local function matched_decoration(queue)
    if not queue then
        return nil
    end

    local first, overlapping
    for _, candidate in ipairs(queue) do
        if candidate.decoration then
            if not first then
                first = candidate
            else
                overlapping = overlapping or {first}
                overlapping[#overlapping + 1] = candidate
            end
        end
    end

    if not first then
        return nil
    end

    if not overlapping then
        return first.decoration
    end

    tab_sort(overlapping, function (a, b)
        return a.depth < b.depth
    end)

    local merged = {}
    for _, candidate in ipairs(overlapping) do
        for _, key in ipairs(WEIGHT_KEYS) do
            local value = candidate.decoration[key]
            if value ~= nil then
                merged[key] = value
            end
        end
    end

    return merged
end


-- Resolves a GraphQL argument literal to a Lua value.
-- Only scalar literals carry a `.value`; list / inputObject nodes do not and are
-- therefore reported as absent. A variable resolves only when the caller passed
-- the request's `variables` map (`resolve_variables`).
local function literal_value(value_node, variables)
    if type(value_node) ~= "table" then
        return nil
    end

    if value_node.kind == "variable" then
        local name = value_node.name and value_node.name.value
        if not name or not variables then
            return nil
        end
        return variables[name]
    end

    return value_node.value
end


local function argument_literal(node, name, variables)
    local args = node.arguments
    if not args then
        return nil
    end

    for _, arg in ipairs(args) do
        if arg.name and arg.name.value == name then
            return literal_value(arg.value, variables)
        end
    end

    return nil
end


-- Returns the numeric value of `name` for this node, or nil when the argument is
-- absent or not usable in arithmetic. `first: "ten"` is client-controlled, so it
-- must not reach the arithmetic: treating it as absent keeps the request on the
-- fast path instead of turning a client-controlled value into a 500.
local function resolve_argument(state, node, name, field_def)
    local value = argument_literal(node, name, state.variables)

    -- By default a query that omits a paginating argument is free, because the
    -- schema default is not consulted; `resolve_variables` opts into reading it.
    if value == nil and state.use_defaults and field_def and field_def.args then
        local arg_def = field_def.args[name]
        value = arg_def and arg_def.default_value
    end

    return tonumber(value)
end


local function node_weights(state, node, deco, field_def)
    if not deco then
        return 1, 1, false
    end

    local node_add = deco.add_value or 1
    local node_mul = deco.mul_value or 1
    local has_quantifier = false

    if deco.add_arguments then
        for _, name in ipairs(deco.add_arguments) do
            local value = resolve_argument(state, node, name, field_def)
            if value then
                node_add = node_add + value
            end
        end
    end

    if deco.mul_arguments then
        for _, name in ipairs(deco.mul_arguments) do
            local value = resolve_argument(state, node, name, field_def)
            if value then
                node_mul = node_mul * value
                has_quantifier = true
            end
        end
    end

    return node_add, node_mul, has_quantifier
end


local each_field
-- Calls fn(child, decoration, field_def, child_type, child_queue) for every field
-- selected by `node`, where `sel_type` is the GraphQL type the selection set
-- belongs to and `queue` the decoration paths still live at this point.
--
-- Fragments are transparent: they carry no cost of their own and they do not move
-- the type cursor or the decoration paths. `... on Droid { name }` therefore
-- matches `<parent type>.name` rather than `Droid.name`: the walk never sees the
-- fragment node, so its `typeCondition` does not take effect.
-- A fragment's `typeCondition` narrows the selection to a concrete type, so the
-- fields inside it belong to that type and not to the abstract one the parent
-- selected. Without moving the cursor, `... on Product { expensive }` under an
-- interface looks `expensive` up on the interface, misses a `Product.expensive`
-- weight and undercharges the query. Only move it when the schema actually knows
-- the type, so an unknown condition degrades instead of losing the cursor.
local function fragment_type(state, node, sel_type)
    local condition = node.typeCondition
    local name = condition and condition.name and condition.name.value
    if name and state.types and state.types[name] then
        return name
    end

    return sel_type
end


function each_field(state, node, sel_type, queue, fn)
    local selection_set = node.selectionSet
    if not selection_set or not selection_set.selections then
        return
    end

    for _, sel in ipairs(selection_set.selections) do
        local kind = sel.kind

        -- Spreading a fragment twice legitimately costs twice, so an acyclic chain
        -- of fragments that each spread the previous one twice expands
        -- exponentially: a document under a kilobyte can otherwise burn seconds of
        -- CPU in the access phase, before any limit has been applied. Bound the
        -- expansion instead, and let the caller reject the request.
        state.budget = state.budget - 1
        if state.budget < 0 then
            state.exhausted = true
            return
        end

        if kind == "field" then
            local name = field_name(sel)
            local deco, field_def, child_type, child_queue
            if name and sel_type then
                local type_def = state.types and state.types[sel_type]
                field_def = type_def and type_def.fields[name]
                child_type = field_def and field_def.type

                if state.deep then
                    child_queue = advance(state.root, queue, child_type, name)
                    deco = matched_decoration(child_queue)
                else
                    -- every path is `<type>.<field>`, so the walk has at most one
                    -- live candidate and collapses to a single lookup
                    deco = state.flat[sel_type .. "." .. name]
                end
            end
            fn(sel, deco, field_def, child_type, child_queue)

        elseif kind == "inlineFragment" then
            each_field(state, sel, fragment_type(state, sel, sel_type), queue, fn)

        elseif kind == "fragmentSpread" then
            local name = sel.name and sel.name.value
            local frag = name and state.fragments[name]
            -- `visiting` breaks fragment definition cycles; a fragment spread twice
            -- in the same selection set is still counted twice.
            if frag and not state.visiting[name] then
                state.visiting[name] = true
                each_field(state, frag, fragment_type(state, frag, sel_type), queue, fn)
                state.visiting[name] = nil
            end
        end

        if state.exhausted then
            return
        end
    end
end


-- cost(node) = ( Σ cost(children) ) × mul_value + add_value
local function complexity_cost(state, node, deco, field_def, sel_type, queue)
    local sum = 0
    each_field(state, node, sel_type, queue,
               function (child, child_deco, child_def, child_type, child_queue)
        sum = sum + complexity_cost(state, child, child_deco, child_def, child_type,
                                 child_queue)
    end)

    local node_add, node_mul = node_weights(state, node, deco, field_def)
    return sum * node_mul + node_add
end


-- Only nodes that actually carry a quantifier argument in this query produce a
-- cost; `mul` is how many times the node is resolved, inherited from its ancestors.
local function node_quantifier_cost(state, node, deco, field_def, sel_type, mul, queue)
    local cost = 0
    local node_add, node_mul, has_quantifier =
            node_weights(state, node, deco, field_def)

    if has_quantifier then
        cost = mul * node_add
        mul = mul * node_mul
    end

    each_field(state, node, sel_type, queue,
               function (child, child_deco, child_def, child_type, child_queue)
        cost = cost + node_quantifier_cost(state, child, child_deco, child_def,
                                           child_type, mul, child_queue)
    end)

    return cost
end


local function root_type(schema, operation)
    if not schema then
        return nil
    end

    if operation.operation == "mutation" then
        return schema.mutation_type
    end

    return schema.query_type
end


---
-- Computes the raw cost of a parsed GraphQL document.
--
-- @tparam string strategy      "complexity" or "node_quantifier"
-- @tparam table  operations    executable operation definitions
-- @tparam table  fragments     named fragment definitions, keyed by name
-- @tparam table  opts          decorations (an index from _M.build_index), schema
--                              (index built by introspection.lua), variables,
--                              use_defaults
-- @treturn number the raw cost, before the `+0.01` floor and `score_factor`
function _M.query_cost(strategy, operations, fragments, opts)
    local index = opts.decorations or EMPTY_INDEX
    local state = {
        flat        = index.flat,
        root        = index.root,
        deep        = index.deep,
        types       = opts.schema and opts.schema.types,
        variables   = opts.variables,
        use_defaults = opts.use_defaults,
        fragments   = fragments,
        visiting    = {},
        budget      = EXPANSION_BUDGET,
        exhausted   = false,
    }

    local cost = 0
    for _, operation in ipairs(operations) do
        local sel_type = root_type(opts.schema, operation)
        -- the operation node seeds the walk from the root type; it has no field
        -- name of its own, so nothing is advanced yet
        local queue = state.deep and sel_type
                      and advance(state.root, nil, sel_type, nil) or nil
        local operation_cost
        if strategy == "node_quantifier" then
            operation_cost = node_quantifier_cost(state, operation, nil, nil,
                                                  sel_type, 1, queue)
        else
            operation_cost = complexity_cost(state, operation, nil, nil, sel_type, queue)
        end
        cost = math_max(cost, operation_cost)

        if state.exhausted then
            return nil, "the query expands past " .. EXPANSION_BUDGET
                        .. " selections", "Invalid graphql request: the query "
                        .. "expands too many selections"
        end
    end

    core.log.info("graphql raw query cost: ", cost, ", strategy: ", strategy)
    return cost
end


return _M
