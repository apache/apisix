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
local dkjson = require("dkjson")
local ipairs = ipairs
local pairs = pairs
local ngx = ngx
local ngx_shared = ngx.shared
local tostring = tostring


local _M = {}

-- Shared dictionary to store connection counts across balancer recreations
local CONN_COUNT_DICT_NAME = "balancer-least-conn"
local conn_count_dict = ngx_shared[CONN_COUNT_DICT_NAME]

-- Initialize shared dictionary at module load time
if not conn_count_dict then
    core.log.error("shared dict '", CONN_COUNT_DICT_NAME, "' not found, ",
                   "please add 'lua_shared_dict ", CONN_COUNT_DICT_NAME, " 10m;' ",
                   "to your nginx configuration")
    error("shared dict '" .. CONN_COUNT_DICT_NAME .. "' not found")
end


local function least_score(a, b)
    return a.score < b.score
end


-- Get the connection count key for a specific upstream and server
local function get_conn_count_key(upstream, server)
    local upstream_id = upstream.id
    if not upstream_id then
        -- Fallback to a hash of the upstream configuration using stable encoding
        upstream_id = ngx.crc32_short(dkjson.encode(upstream))
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


-- Set the connection count for a server in shared dict
local function set_server_conn_count(upstream, server, count)
    local key = get_conn_count_key(upstream, server)
    local ok, err = conn_count_dict:set(key, count)
    if not ok then
        core.log.error("failed to set connection count for ", server, ": ", err)
    else
        core.log.debug("set connection count for server ", server, " to ", count)
    end
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
local function cleanup_stale_conn_counts(upstream, current_servers)
    local upstream_id = upstream.id
    if not upstream_id then
        upstream_id = ngx.crc32_short(dkjson.encode(upstream))
    end
    
    local prefix = "conn_count:" .. tostring(upstream_id) .. ":"
    core.log.debug("cleaning up stale connection counts with prefix: ", prefix)
    local keys, err = conn_count_dict:get_keys(0)  -- Get all keys
    if err then
        core.log.error("failed to get keys from shared dict: ", err)
        return
    end
    
    for _, key in ipairs(keys or {}) do
        if core.string.has_prefix(key, prefix) then
            local server = key:sub(#prefix + 1)
            if not current_servers[server] then
                -- This server is no longer in the upstream, clean it up
                local ok, delete_err = conn_count_dict:delete(key)
                if not ok and delete_err then
                    core.log.error("failed to delete stale connection count for server ", server, ": ", delete_err)
                else
                    core.log.info("cleaned up stale connection count for server: ", server)
                end
            end
        end
    end
end


function _M.new(up_nodes, upstream)
    core.log.debug("creating new least_conn balancer for upstream: ", upstream.id or "no-id")
    local servers_heap = binaryHeap.minUnique(least_score)
    
    -- Clean up stale connection counts for removed servers
    cleanup_stale_conn_counts(upstream, up_nodes)
    
    -- First pass: collect existing connection counts and identify new servers
    local server_conn_counts = {}
    local existing_servers = {}
    local new_servers = {}
    local total_existing_connections = 0
    local existing_server_count = 0
    
    for server, weight in pairs(up_nodes) do
        local conn_count = get_server_conn_count(upstream, server)
        server_conn_counts[server] = conn_count
        
        if conn_count > 0 then
            existing_servers[server] = true
            total_existing_connections = total_existing_connections + conn_count
            existing_server_count = existing_server_count + 1
        else
            new_servers[server] = true
        end
    end
    
    -- Calculate average connections for existing servers to help balance new servers
    local avg_existing_connections = 0
    if existing_server_count > 0 then
        avg_existing_connections = total_existing_connections / existing_server_count
    end
    
    -- For new servers, initialize with a balanced connection count
    -- This helps prevent all new connections from going to new servers
    local new_server_count = 0
    for _ in pairs(new_servers) do
        new_server_count = new_server_count + 1
    end
    
    if new_server_count > 0 and avg_existing_connections > 0 then
        -- Initialize new servers with a connection count that promotes balanced distribution
        -- Use a higher fraction to ensure existing servers still get some new connections
        -- The goal is to balance load while still respecting the least_conn principle
        local initial_conn_count = math.floor(avg_existing_connections * 0.8)
        core.log.info("initializing ", new_server_count, " new servers with ", 
                     initial_conn_count, " connections each (avg existing: ", 
                     avg_existing_connections, ")")
        
        for server in pairs(new_servers) do
            set_server_conn_count(upstream, server, initial_conn_count)
            server_conn_counts[server] = initial_conn_count
        end
    end
    
    -- Second pass: create heap with balanced connection counts
    for server, weight in pairs(up_nodes) do
        local base_score = 1 / weight
        local conn_count = server_conn_counts[server]
        -- Calculate the actual score including existing connections
        local score = base_score + (conn_count * (1 / weight))
        
        core.log.info("initializing server ", server, " with weight ", weight, 
                     ", base_score ", base_score, ", conn_count ", conn_count, 
                     ", final_score ", score, 
                     ", is_new: ", new_servers[server] and "true" or "false")
        
        -- Note: the argument order of insert is different from others
        servers_heap:insert({
            server = server,
            effect_weight = 1 / weight,
            score = score,
        }, server)
    end

    return {
        upstream = upstream,
        get = function (ctx)
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

            core.log.debug("selected server: ", server, " with current score: ", info.score)
            info.score = info.score + info.effect_weight
            servers_heap:update(server, info)
            -- Increment connection count in shared dict
            incr_server_conn_count(upstream, server, 1)
            return server
        end,
        after_balance = function (ctx, before_retry)
            local server = ctx.balancer_server
            local info = servers_heap:valueByPayload(server)
            core.log.debug("after_balance for server: ", server, ", before_retry: ", before_retry)
            info.score = info.score - info.effect_weight
            servers_heap:update(server, info)
            -- Decrement connection count in shared dict
            incr_server_conn_count(upstream, server, -1)

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
        before_retry_next_priority = function (ctx)
            if ctx.balancer_tried_servers then
                core.tablepool.release("balancer_tried_servers", ctx.balancer_tried_servers)
                ctx.balancer_tried_servers = nil
            end
        end,
    }
end


return _M
