-- Original Authors: Shiv Nagarajan & Scott Francis
-- Accessed: March 12, 2018
-- Inspiration drawn from:
-- https://github.com/twitter/finagle/blob/1bc837c4feafc0096e43c0e98516a8e1c50c4421
--   /finagle-core/src/main/scala/com/twitter/finagle/loadbalancer/PeakEwma.scala
local core = require("apisix.core")
local resty_lock = require("resty.lock")

local ngx = ngx
local ngx_shared = ngx.shared
local ngx_now = ngx.now
local math = math
local pairs = pairs

local DECAY_TIME = 10 -- this value is in seconds
local LOCK_KEY = ":ewma_key"

local shm_ewma = ngx_shared.balancer_ewma
local shm_last_touched_at = ngx_shared.balancer_ewma_last_touched_at

local lrucache_addr = core.lrucache.new({ttl = 300, count = 1024})
local lrucache_trans_format = core.lrucache.new({ttl = 300, count = 256})

local ewma_lock, ewma_lock_err = resty_lock:new("balancer_ewma_locks",
                                                {timeout = 0, exptime = 0.1})
if not ewma_lock then
    error(ewma_lock_err)
end

local _M = {name = "ewma"}

local function lock(upstream)
    local _, err = ewma_lock:lock(upstream .. LOCK_KEY)
    if err then
        if err ~= "timeout" then
            core.log.error("EWMA Balancer failed to lock: ", err)
        end
    end

    return err
end

local function unlock()
    local ok, err = ewma_lock:unlock()
    if not ok then
        core.log.error("EWMA Balancer failed to unlock: ", err)
    end

    return err
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
        core.log.warn("shm_last_touched_at:set failed: ", err)
    end
    if forcible then
        core.log
            .warn("shm_last_touched_at:set valid items forcibly overwritten")
    end

    success, err, forcible = shm_ewma:set(upstream, ewma)
    if not success then
        core.log.warn("shm_ewma:set failed: ", err)
    end
    if forcible then
        core.log.warn("shm_ewma:set valid items forcibly overwritten")
    end
end

local function get_or_update_ewma(upstream, rtt, update)
    local lock_err = nil
    if update then
        lock_err = lock(upstream)
    end

    local ewma = shm_ewma:get(upstream) or 0
    if lock_err ~= nil then
        return ewma, lock_err
    end

    local now = ngx_now()
    local last_touched_at = ngx.shared.balancer_ewma_last_touched_at:get(
                                upstream) or 0
    ewma = decay_ewma(ewma, last_touched_at, rtt, now)

    if not update then
        return ewma, nil
    end

    store_stats(upstream, ewma, now)

    unlock()

    return ewma, nil
end

local function get_upstream_name(upstream)
    return upstream.host .. ":" .. upstream.port
end

local function score(upstream)
    -- Original implementation used names
    -- Endpoints don't have names, so passing in IP:Port as key instead
    local upstream_name = get_upstream_name(upstream)
    return get_or_update_ewma(upstream_name, 0, false)
end

local function parse_addr(addr)
    local host, port, err = core.utils.parse_addr(addr)
    return {host = host, port = port}, err
end

local function _trans_format(up_nodes)
    -- trans
    -- {"1.2.3.4:80":100,"5.6.7.8:8080":100}
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

    if not up_nodes or core.table.nkeys(up_nodes) == 0 then
        return nil, 'up_nodes empty'
    end

    peers = lrucache_trans_format(ctx.upstream_key, ctx.upstream_version,
                                  _trans_format, up_nodes)
    if not peers then
        return nil, 'up_nodes trans error'
    end

    local endpoint = peers[1]

    if #peers > 1 then
        local a, b = math.random(1, #peers), math.random(1, #peers - 1)
        if b >= a then
            b = b + 1
        end

        local backendpoint
        endpoint, backendpoint = peers[a], peers[b]
        if score(endpoint) > score(backendpoint) then
            endpoint = backendpoint
        end
    end

    return get_upstream_name(endpoint)
end

local function _ewma_after_balance(ctx, before_retry)
    if before_retry then
        -- don't count tries which fail to complete
        return nil
    end

    local response_time = ctx.var.upstream_response_time or 0
    local connect_time = ctx.var.upstream_connect_time or 0
    local rtt = connect_time + response_time
    local upstream = ctx.var.upstream_addr

    if not upstream then
        return nil, "no upstream addr found"
    end

    return get_or_update_ewma(upstream, rtt, true)
end

function _M.new(up_nodes, upstream)
    if not shm_ewma or not shm_last_touched_at then
        return nil, "dictionary not find"
    end

    return {
        upstream = upstream,
        get = function(ctx)
            return _ewma_find(ctx, up_nodes)
        end,
        after_balance = _ewma_after_balance
    }
end

return _M
