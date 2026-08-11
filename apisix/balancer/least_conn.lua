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
local binaryHeap = require("binaryheap")
local ipairs = ipairs
local pairs = pairs


local _M = {}


-- Per-worker balancing state, shared by every picker built for the same upstream.
--
-- A picker is cached by the upstream version, so it is thrown away whenever the
-- upstream changes: scaling, a config update, or a health status flip. The
-- requests that are still in flight keep the picker they were routed with, and
-- release their server on that picker in the log phase. If the heap lived inside
-- the picker, the rebuilt one would never see those releases: the connections
-- established before the rebuild would be forgotten on creation and then, once
-- they closed, decremented on a heap nobody reads anymore. Long-lived
-- connections (WebSocket) would keep the load skewed on the original nodes and
-- least_conn would degrade to round-robin. See #12217.
--
-- Keeping the heap and the in-flight counts here, keyed by something stable
-- across scaling, gives every generation of pickers a single view of the load.
--
-- The values are weak, which is exactly the lifetime this state needs. A picker
-- holds its state, an in-flight request holds the picker it was routed with, and
-- the picker cache holds the current one - so a state survives for as long as
-- anything can still release a connection into it. Once nothing references it
-- there is no connection left to count, and dropping it costs nothing. That also
-- means there is no size to tune and no eviction that could quietly forget a busy
-- upstream, which is what an LRU would do here: it would rank states by how
-- recently they were rebuilt, and a stable upstream holding many long-lived
-- connections is precisely the one that is never rebuilt.
local states = setmetatable({}, {__mode = "v"})


local function least_score(a, b)
    return a.score < b.score
end


local function new_state()
    return {
        heap = binaryHeap.minUnique(least_score),
        -- server -> in-flight connections, only holds positive counts
        conns = {},
        -- server -> true, mirrors the payloads currently in the heap
        members = {},
    }
end


local function update_score(state, server)
    local info = state.heap:valueByPayload(server)
    -- the server may have left the upstream while it still held connections
    if not info then
        return
    end

    info.score = (1 + (state.conns[server] or 0)) * info.effect_weight
    state.heap:update(server, info)
end


-- Align the long-lived heap with the current node set, keeping the in-flight
-- counts of the nodes that survive. A node that is added back later (scaled in
-- again, or reported healthy again) gets its score restored from `conns`.
local function sync_nodes(state, up_nodes)
    local heap = state.heap

    for server in pairs(state.members) do
        if not up_nodes[server] then
            heap:remove(server)
            state.members[server] = nil
        end
    end

    for server, weight in pairs(up_nodes) do
        local effect_weight = 1 / weight
        local info = heap:valueByPayload(server)
        if info then
            info.effect_weight = effect_weight
        else
            -- Note: the argument order of insert is different from others
            heap:insert({
                server = server,
                effect_weight = effect_weight,
                score = effect_weight,
            }, server)
            state.members[server] = true
        end
        -- one place decides what a score is worth
        update_score(state, server)
    end
end


function _M.new(up_nodes, upstream, priority)
    -- resource_key identifies the upstream and is stable across node scaling, unlike
    -- the picker version which changes whenever the nodes change. Do not fall back to
    -- resource_id: it is a bare id, so a route and an upstream sharing one would land
    -- on the same heap and evict each other's nodes
    local up_key = upstream.resource_key
    local state
    if up_key and priority then
        -- each priority level owns a disjoint node set, so it needs its own heap.
        -- Do not default the priority: a caller that does not name one has a node
        -- set we cannot place, and folding it into level 0 would let sync_nodes
        -- evict that level's nodes from the heap it shares
        local state_key = up_key .. "#" .. priority
        state = states[state_key]
        if not state then
            state = new_state()
            states[state_key] = state
        end
    else
        -- no stable identity, fall back to a state private to this picker
        state = new_state()
    end

    sync_nodes(state, up_nodes)

    local servers_heap = state.heap
    local conns = state.conns

    return {
        upstream = upstream,
        get = function (ctx)
            local tried = ctx.balancer_tried_servers
            local server, info, err
            local skipped

            while true do
                server, info = servers_heap:peek()
                -- we need to let the retry > #nodes so this branch can be hit and
                -- the request will retry next priority of nodes
                if server == nil then
                    err = "all upstream servers tried"
                    break
                end

                -- the heap is shared with the pickers built for later versions of
                -- the upstream, so it can hold nodes this request's conf does not
                -- know about. Only hand out the ones it does
                if up_nodes[server] and not (tried and tried[server]) then
                    break
                end

                servers_heap:pop()
                if not skipped then
                    skipped = {}
                end
                core.table.insert(skipped, info)
            end

            if skipped then
                for _, skipped_info in ipairs(skipped) do
                    servers_heap:insert(skipped_info, skipped_info.server)
                end
            end

            if not server then
                return nil, err
            end

            conns[server] = (conns[server] or 0) + 1
            update_score(state, server)
            return server
        end,
        after_balance = function (ctx, before_retry)
            -- the release is what makes the request stop holding the server, so drop
            -- the reference here instead of leaving every caller to remember. A caller
            -- that goes on to retry gets a fresh one from the next pick
            local server = ctx.balancer_server
            ctx.balancer_server = nil

            if server then
                local count = (conns[server] or 0) - 1
                if count < 0 then
                    -- a release with no matching pick. The store below floors the
                    -- count either way, so the score cannot be corrupted - but the
                    -- accounting is wrong and it should not pass in silence
                    core.log.error("released a connection never picked on ", server)
                end
                conns[server] = count > 0 and count or nil
                update_score(state, server)
            end

            if not before_retry then
                if ctx.balancer_tried_servers then
                    core.tablepool.release("balancer_tried_servers", ctx.balancer_tried_servers)
                    ctx.balancer_tried_servers = nil
                end

                return nil
            end

            if not server then
                return nil
            end

            if not ctx.balancer_tried_servers then
                ctx.balancer_tried_servers = core.tablepool.fetch("balancer_tried_servers", 0, 2)
            end

            ctx.balancer_tried_servers[server] = true
        end,
        before_retry_next_priority = function (ctx)
            if ctx.balancer_tried_servers then
                core.tablepool.release("balancer_tried_servers", ctx.balancer_tried_servers)
                ctx.balancer_tried_servers = nil
            end
        end,
    }
end


return _M
