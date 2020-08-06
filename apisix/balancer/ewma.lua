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

local resty_lock = require("resty.lock")
local core = require("apisix.core")
local ngx_shared = ngx.shared

local _M = {}
local DECAY_TIME = 10 -- this value is in seconds
local LOCK_KEY = ":ewma_key"
local PICK_SET_SIZE = 2
local ewma_lock, ewma_lock_err
local shm_ewma = ngx_shared.balancer_ewma
local shm_last_touched_at= ngx_shared.balancer_ewma_last_touched_at

local function lock(upstream)
    local _, err = ewma_lock:lock(upstream .. LOCK_KEY)
    if err then
        if err ~= "timeout" then
            core.log.error("EWMA Balancer failed to lock:", tostring(err))
        end
        return false, err
    end
    return true
end


local function unlock()
    local ok, err = ewma_lock:unlock()
    if not ok then
        core.log.error("EWMA Balancer failed to unlock:", tostring(err))
        return false, err
    end
    return true
end


local function decay_ewma(ewma, last_touched_at, rtt, now)
    local td = now - last_touched_at
    td = (td > 0) and td or 0
    local weight = math.exp(-td / DECAY_TIME)

    ewma = ewma * weight + rtt * (1.0 - weight)
    return ewma
end


local function store_stats(upstream, ewma, now)
    local success, err, forcible = shm_last_touched_at:set(upstream, now)
    if not success then
        core.log.warn("balancer_ewma_last_touched_at:set failed ", err)
    end
    if forcible then
        core.log.warn("balancer_ewma_last_touched_at:set valid items forcibly overwritten")
    end

    success, err, forcible = shm_ewma:set(upstream, ewma)
    if not success then
        core.log.warn("balancer_ewma:set failed ", err)
    end
    if forcible then
        core.log.warn("balancer_ewma:set valid items forcibly overwritten")
    end
end


local function get_or_update_ewma(upstream, rtt, update)
    local lock_ok, err = nil
    if update then
        lock_ok, err = lock(upstream)
    end
    local ewma = shm_ewma:get(upstream) or 0
    if not lock_ok then
        return ewma, err
    end

    local now = ngx.now()
    local last_touched_at = shm_last_touched_at:get(upstream) or 0
    ewma = decay_ewma(ewma, last_touched_at, rtt, now)

    if not update then
        return ewma
    end

    store_stats(upstream, ewma, now)

    unlock()

    return ewma
end


local function score(upstream)
    -- Original implementation used names
    -- Endpoints don't have names, so passing in IP:Port as key instead
    local upstream_name = upstream.address .. ":" .. upstream.port
    return get_or_update_ewma(upstream_name, 0, false)
end


-- implementation similar to https://en.wikipedia.org/wiki/Fisher%E2%80%93Yates_shuffle
-- or https://en.wikipedia.org/wiki/Random_permutation
-- loop from 1 .. k
-- pick a random value r from the remaining set of unpicked values (i .. n)
-- swap the value at position i with the value at position r
local function shuffle_peers(peers, k)
    for i = 1, k do
        local rand_index = math.random(i, #peers)
        peers[i], peers[rand_index] = peers[rand_index], peers[i]
    end
    -- peers[1 .. k] will now contain a randomly selected k from #peers
end


local function pick_and_score(peers, k)
    shuffle_peers(peers, k)
    local lowest_score_index = 1
    local lowest_score = score(peers[lowest_score_index])
    for i = 2, k do
        local new_score = score(peers[i])
        if new_score < lowest_score then
            lowest_score_index, lowest_score = i, new_score
        end
    end
    return peers[lowest_score_index], lowest_score
end


-- slow_start_ewma is something we use to avoid sending too many requests
-- to the newly introduced endpoints. We currently use average ewma values
-- of existing endpoints.
local function calculate_slow_start_ewma(self)
    local total_ewma = 0
    local endpoints_count = 0

    for _, endpoint in pairs(self.peers) do
        local endpoint_string = endpoint.address .. ":" .. endpoint.port
        local ewma = shm_ewma:get(endpoint_string)

        if ewma then
            endpoints_count = endpoints_count + 1
            total_ewma = total_ewma + ewma
        end
    end

    if endpoints_count == 0 then
        ngx.log(ngx.INFO, "no ewma value exists for the endpoints")
        return nil
    end

    return total_ewma / endpoints_count
end


local function _trans_format(t1)
    -- trans
    --{"1.2.3.4:80":100,"5.6.7.8:8080":100}
    -- into
    -- [{"address":"1.2.3.4","port":"80"},{"address":"5.6.7.8","port":"8080"}]
    local t2 = {}
    local addr, port, err
    local k,_

    for k,_ in pairs(t1) do
        addr, port, err = core.utils.parse_addr(k)
        if not err then
            t2[#t2+1] = {address = addr, port = tostring(port)}
        else
            core.log.error('parse_addr error: ',k,err)
        end
    end
    return next(t2) and t2 or nil
end


local function _ewma_find(up_nodes)
    local peers
    local endpoint, ewma_score
    local err

    if not ewma_lock then
        ewma_lock, ewma_lock_err = resty_lock:new("balancer_ewma_locks", {timeout = 0, exptime = 0.1})
    end
    if not ewma_lock then
        return nil, ewma_lock_err
    end
    peers = _trans_format(up_nodes)
    if not peers then
        err = 'up_nodes error'
        return nil, err
    end
    endpoint, ewma_score = peers[1]
    if #peers > 1 then
        local k = (#peers < PICK_SET_SIZE) and #peers or PICK_SET_SIZE
        endpoint, ewma_score = pick_and_score(peers, k)
    end
    --ngx.var.balancer_ewma_score = ewma_score

    return endpoint.address .. ":" .. endpoint.port
end


local function _ewma_after_balance()
    local response_time = tonumber(ngx.var.upstream_response_time) or 0
    local connect_time = tonumber(ngx.var.upstream_connect_time) or 0
    local rtt = connect_time + response_time
    local upstream = ngx.var.upstream_addr
    local err

    if not ewma_lock then
        ewma_lock, ewma_lock_err = resty_lock:new("balancer_ewma_locks", {timeout = 0, exptime = 0.1})
    end
    if not ewma_lock then
        return nil, ewma_lock
    end
    if not upstream then
        err = "no upstream addr found"
        return nil, err
    end
    return get_or_update_ewma(upstream, rtt, true)
end


function _M.new(up_nodes, upstream)
    if not shm_ewma
       or not shm_last_touched_at then
        return nil, "dictionary not find"
    end

    return {
        upstream = upstream,
        get = function ()
            return _ewma_find(up_nodes)
        end,
        after_balance = function()
            return _ewma_after_balance()
        end
    }
end


return _M
