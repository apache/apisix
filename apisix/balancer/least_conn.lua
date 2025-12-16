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
local ngx = ngx
local ngx_shared = ngx.shared
local tostring = tostring

local _M = {}

-- Shared dictionary to store connection counts across balancer recreations
local CONN_COUNT_DICT_NAME = "balancer-least-conn"
local conn_count_dict

local function least_score(a, b)
    return a.score < b.score
end

-- Get the connection count key for a specific upstream and server
local function get_conn_count_key(upstream, server)
    local upstream_id = upstream.id
    if not upstream_id then
        -- Fallback to a hash of the upstream configuration using stable encoding
        upstream_id = ngx.crc32_short(core.json.stably_encode(upstream))
        core.log.debug("generated upstream_id from hash: ", upstream_id)
    end
    local key = "conn_count:" .. tostring(upstream_id) .. ":" .. server
    core.log.debug("generated connection count key: ", key)
    return key
end

-- Get the current connection count for a server from shared dict
local function get_server_conn_count(upstream, server)
    local key = get_conn_count_key(upstream, server)
    local count, err = conn_count_dict:get(key)
    if err then
        core.log.error("failed to get connection count for ", server, ": ", err)
        return 0
    end
    local result = count or 0
    core.log.debug("retrieved connection count for server ", server, ": ", result)
    return result
end

-- Increment the connection count for a server
local function incr_server_conn_count(upstream, server, delta)
    local key = get_conn_count_key(upstream, server)
    local new_count, err = conn_count_dict:incr(key, delta or 1, 0)
    if not new_count then
        core.log.error("failed to increment connection count for ", server, ": ", err)
        return 0
    end
    core.log.debug("incremented connection count for server ", server, " by ", delta or 1,
            ", new count: ", new_count)
    return new_count
end

-- Clean up connection counts for servers that are no longer in the upstream
-- Uses a lightweight strategy: only cleanup when explicitly needed
local function cleanup_stale_conn_counts(upstream, current_servers)
    local upstream_id = upstream.id
    if not upstream_id then
        upstream_id = ngx.crc32_short(core.json.stably_encode(upstream))
    end

    local prefix = "conn_count:" .. tostring(upstream_id) .. ":"
    core.log.debug("lightweight cleanup for upstream: ", upstream_id)

    -- Strategy: Only clean up entries we know about (current servers)
    -- This avoids expensive get_keys() calls entirely

    local cleaned_count = 0

    -- For each current server, verify its connection count is still valid
    -- If count is zero, we can optionally remove it to free memory
    for server, _ in pairs(current_servers) do
        local key = prefix .. server
        local count, err = conn_count_dict:get(key)

        if err then
            core.log.error("failed to get connection count for ", server, ": ", err)
        elseif count and count == 0 then
            -- Remove zero-count entries to prevent memory accumulation
            local ok, delete_err = conn_count_dict:delete(key)
            if ok and not delete_err then
                cleaned_count = cleaned_count + 1
                core.log.debug("removed zero-count entry for server: ", server)
            elseif delete_err then
                core.log.warn("failed to remove zero-count entry for ", server, ": ", delete_err)
            end
        end
    end

    -- Note: Stale entries for removed servers will naturally expire over time
    -- or can be cleaned up by the global cleanup_all() function
    if cleaned_count > 0 then
        core.log.debug("cleaned up ", cleaned_count, " zero-count entries")
    end
end

function _M.new(up_nodes, upstream)
    if not conn_count_dict then
        conn_count_dict = ngx_shared[CONN_COUNT_DICT_NAME]
    end

    -- Enable persistent counting only when explicitly requested
    -- This ensures complete backward compatibility with existing behavior
    local use_persistent_counting = conn_count_dict ~= nil and
        upstream.persistent_conn_counting == true

    if not use_persistent_counting and conn_count_dict then
        core.log.debug("shared dict available but persistent counting not enabled for scheme: http,",
                    "using traditional least_conn mode")
    elseif use_persistent_counting and not conn_count_dict then
        core.log.warn("persistent counting requested but shared dict '",
        CONN_COUNT_DICT_NAME, "' not found, using traditional least_conn mode")
        use_persistent_counting = false
    end

    local servers_heap = binaryHeap.minUnique(least_score)

    if use_persistent_counting then
        -- Clean up stale connection counts for removed servers
        cleanup_stale_conn_counts(upstream, up_nodes)
    end

    for server, weight in pairs(up_nodes) do
        local score
        if use_persistent_counting then
            -- True least connection mode: use persistent connection counts
            local conn_count = get_server_conn_count(upstream, server)
            score = (conn_count + 1) / weight
            core.log.debug("initializing server ", server, " with persistent counting",
                    " | weight: ", weight, " | conn_count: ", conn_count, " | score: ", score)
        else
            -- Traditional mode: use original weighted round-robin behavior
            score = 1 / weight
        end

        -- Note: the argument order of insert is different from others
        servers_heap:insert({
            server = server,
            weight = weight,
            effect_weight = 1 / weight,  -- For backward compatibility
            score = score,
            use_persistent_counting = use_persistent_counting,
        }, server)
    end

    return {
        upstream = upstream,
        get = function(ctx)
            local server, info, err
            if ctx.balancer_tried_servers then
                local tried_server_list = {}
                while true do
                    server, info = servers_heap:peek()
                    -- we need to let the retry > #nodes so this branch can be hit and
                    -- the request will retry next priority of nodes
                    if server == nil then
                        err = "all upstream servers tried"
                        break
                    end

                    if not ctx.balancer_tried_servers[server] then
                        break
                    end

                    servers_heap:pop()
                    core.table.insert(tried_server_list, info)
                end

                for _, info in ipairs(tried_server_list) do
                    servers_heap:insert(info, info.server)
                end
            else
                server, info = servers_heap:peek()
            end

            if not server then
                return nil, err
            end

            if info.use_persistent_counting then
                -- True least connection mode: update based on persistent connection counts
                local current_conn_count = get_server_conn_count(upstream, server)
                info.score = (current_conn_count + 1) / info.weight
                servers_heap:update(server, info)
                incr_server_conn_count(upstream, server, 1)
            else
                -- Traditional mode: use original weighted round-robin logic
                info.score = info.score + info.effect_weight
                servers_heap:update(server, info)
            end
            return server
        end,
        after_balance = function(ctx, before_retry)
            local server = ctx.balancer_server
            local info = servers_heap:valueByPayload(server)
            if not info then
                core.log.error("server info not found for: ", server)
                return
            end

            if info.use_persistent_counting then
                -- True least connection mode: update based on persistent connection counts
                incr_server_conn_count(upstream, server, -1)
                local current_conn_count = get_server_conn_count(upstream, server)
                info.score = (current_conn_count + 1) / info.weight
                if info.score < 0 then
                    -- Prevent negative scores
                    info.score = 0
                end
            else
                -- Traditional mode: use original weighted round-robin logic
                info.score = info.score - info.effect_weight
            end
            servers_heap:update(server, info)

            if not before_retry then
                if ctx.balancer_tried_servers then
                    core.tablepool.release("balancer_tried_servers", ctx.balancer_tried_servers)
                    ctx.balancer_tried_servers = nil
                end

                return nil
            end

            if not ctx.balancer_tried_servers then
                ctx.balancer_tried_servers = core.tablepool.fetch("balancer_tried_servers", 0, 2)
            end

            ctx.balancer_tried_servers[server] = true
        end,
        before_retry_next_priority = function(ctx)
            if ctx.balancer_tried_servers then
                core.tablepool.release("balancer_tried_servers", ctx.balancer_tried_servers)
                ctx.balancer_tried_servers = nil
            end
        end,
    }
end

local function cleanup_all_conn_counts()
    if not conn_count_dict then
        conn_count_dict = ngx_shared[CONN_COUNT_DICT_NAME]
    end

    if not conn_count_dict then
        -- No shared dict available, nothing to cleanup
        return
    end

    -- Use batched cleanup to avoid performance issues with large dictionaries
    -- Process keys in batches to limit memory usage and execution time
    local batch_size = 100  -- Process 100 keys at a time
    local total_cleaned = 0
    local processed_count = 0
    local has_more = true

    while has_more do
        local keys, err = conn_count_dict:get_keys(batch_size)
        if err then
            core.log.error("failed to get keys from shared dict during cleanup: ", err)
            return
        end

        if not keys or #keys == 0 then
            break
        end

        local batch_cleaned = 0
        for _, key in ipairs(keys) do
            processed_count = processed_count + 1
            if core.string.has_prefix(key, "conn_count:") then
                local ok, delete_err = conn_count_dict:delete(key)
                if not ok and delete_err then
                    core.log.warn("failed to delete connection count key during cleanup: ",
                    key, ", error: ", delete_err)
                else
                    batch_cleaned = batch_cleaned + 1
                    total_cleaned = total_cleaned + 1
                end
            end
        end

        -- Yield control periodically to avoid blocking
        if processed_count % 1000 == 0 then
            ngx.sleep(0.001)  -- 1ms yield
        end

        -- If we got fewer keys than batch_size, we're done
        if #keys < batch_size then
            has_more = false
        end
    end

    if total_cleaned > 0 then
        core.log.info("cleaned up ", total_cleaned, " connection count entries from shared dict")
    end
end

function _M.cleanup_all()
    cleanup_all_conn_counts()
end

return _M
