-- Original Authors: Shiv Nagarajan & Scott Francis
-- Accessed: March 12, 2018
-- Inspiration drawn from:
-- https://github.com/twitter/finagle/blob/1bc837c4feafc0096e43c0e98516a8e1c50c4421
--   /finagle-core/src/main/scala/com/twitter/finagle/loadbalancer/PeakEwma.scala

local core = require("apisix.core")
local ngx = ngx
local ngx_shared = ngx.shared
local ngx_now = ngx.now
local math = math
local pairs = pairs
local next = next
local tonumber = tonumber

local _M = {}
local DECAY_TIME = 10 -- this value is in seconds

local shm_ewma = ngx_shared.balancer_ewma
local shm_last_touched_at= ngx_shared.balancer_ewma_last_touched_at

local lrucache_addr = core.lrucache.new({
    ttl = 300, count = 1024
})
local lrucache_trans_format = core.lrucache.new({
    ttl = 300, count = 256
})


local function decay_ewma(ewma, last_touched_at, rtt, now)
    local td = now - last_touched_at
    td = math.max(td, 0)
    local weight = math.exp(-td / DECAY_TIME)

    ewma = ewma * weight + rtt * (1.0 - weight)
    return ewma
end


local function store_stats(upstream, ewma, now)
    local success, err, forcible = shm_last_touched_at:set(upstream, now)
    if not success then
        core.log.error("balancer_ewma_last_touched_at:set failed ", err)
    end
    if forcible then
        core.log.warn("balancer_ewma_last_touched_at:set valid items forcibly overwritten")
    end

    success, err, forcible = shm_ewma:set(upstream, ewma)
    if not success then
        core.log.error("balancer_ewma:set failed ", err)
    end
    if forcible then
        core.log.warn("balancer_ewma:set valid items forcibly overwritten")
    end
end


local function get_or_update_ewma(upstream, rtt, update)
    local ewma = shm_ewma:get(upstream) or 0
    local now = ngx_now()
    local last_touched_at = shm_last_touched_at:get(upstream) or 0
    ewma = decay_ewma(ewma, last_touched_at, rtt, now)

    if not update then
        return ewma
    end

    store_stats(upstream, ewma, now)

    return ewma
end


local function score(upstream)
    -- Original implementation used names
    -- Endpoints don't have names, so passing in host:Port as key instead
    local upstream_name = upstream.host .. ":" .. upstream.port
    return get_or_update_ewma(upstream_name, 0, false)
end


local function pick_and_score(peers)
    local lowest_score_index = 1
    local lowest_score = score(peers[lowest_score_index])
    for i = 2, #peers do
        local new_score = score(peers[i])
        if new_score < lowest_score then
            lowest_score_index, lowest_score = i, new_score
        end
    end

    return peers[lowest_score_index], lowest_score
end


local function parse_addr(addr)
    local host, port, err = core.utils.parse_addr(addr)
    return {host = host, port = port}, err
end


local function _trans_format(up_nodes)
    -- trans
    --{"1.2.3.4:80":100,"5.6.7.8:8080":100}
    -- into
    -- [{"host":"1.2.3.4","port":"80"},{"host":"5.6.7.8","port":"8080"}]
    local peers = {}
    local res, err

    for addr, _ in pairs(up_nodes) do
        res, err = lrucache_addr(addr, nil, parse_addr, addr)
        if not err then
            core.table.insert(peers, res)
        else
            core.log.error('parse_addr error: ', addr, err)
        end
    end

    return next(peers) and peers or nil
end


local function _ewma_find(ctx, up_nodes)
    local peers
    local endpoint

    if not up_nodes
       or core.table.nkeys(up_nodes) == 0 then
        return nil, 'up_nodes empty'
    end

    peers = lrucache_trans_format(ctx.upstream_key, ctx.upstream_version,
                                  _trans_format, up_nodes)
    if not peers then
        return nil, 'up_nodes trans error'
    end

    if #peers > 1 then
        endpoint = pick_and_score(peers)
    else
        endpoint = peers[1]
    end

    return endpoint.host .. ":" .. endpoint.port
end


local function _ewma_after_balance(ctx)
    local response_time = tonumber(ctx.var.upstream_response_time) or 0
    local connect_time = tonumber(ctx.var.upstream_connect_time) or 0
    local rtt = connect_time + response_time
    local upstream = ctx.var.upstream_addr

    if not upstream then
        return nil, "no upstream addr found"
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
        get = function (ctx)
            return _ewma_find(ctx, up_nodes)
        end,
        after_balance = _ewma_after_balance
    }
end


return _M
