local healthcheck = require("resty.healthcheck")
local roundrobin  = require("resty.roundrobin")
local resty_chash = require("resty.chash")
local balancer = require("ngx.balancer")
local core = require("apisix.core")
local worker_exiting = ngx.worker.exiting
local sub_str = string.sub
local find_str = string.find
local upstreams_etcd
local error = error
local str_char = string.char
local str_gsub = string.gsub
local pairs = pairs
local tonumber = tonumber
local tostring = tostring


local module_name = "balancer"
local lrucache_server_picker = core.lrucache.new({ttl = 300, count = 256})


local _M = {
    version = 0.1,
    name = module_name,
}


local function parse_addr(addr)
    local pos = find_str(addr, ":", 1, true)
    if not pos then
        return addr, 80
    end

    local host = sub_str(addr, 1, pos - 1)
    local port = sub_str(addr, pos + 1)
    return host, tonumber(port)
end


local function fetch_health_nodes(upstream)
    if not upstream.checks then
        return upstream.nodes
    end

    local host = upstream.checks and upstream.checks.host
    local checker = upstream.checker
    local up_nodes = core.table.new(0, #upstream.nodes)

    for addr, weight in pairs(upstream.nodes) do
        local ip, port = parse_addr(addr)
        local ok = checker:get_target_status(ip, port, host)
        if ok then
            up_nodes[addr] = weight
        end
    end

    if core.table.nkeys(up_nodes) == 0 then
        core.log.warn("all upstream nodes is unhealth, use default")
        up_nodes = upstream.nodes
    end
    return up_nodes
end


local function create_server_picker(upstream)
    core.log.info("create create_obj, type: ", upstream.type,
                  " nodes: ", core.json.delay_encode(upstream.nodes))

    if upstream.type == "roundrobin" then
        local up_nodes = fetch_health_nodes(upstream)
        core.log.info("upstream nodes: ", core.json.delay_encode(up_nodes))

        local picker = roundrobin:new(up_nodes)
        return {
            get = function ()
                return picker:find()
            end
        }
    end

    if upstream.type == "chash" then
        local up_nodes = fetch_health_nodes(upstream)
        local str_null = str_char(0)

        local servers, nodes = {}, {}
        for serv, weight in pairs(up_nodes) do
            local id = str_gsub(serv, ":", str_null)

            servers[id] = serv
            nodes[id] = weight
        end

        local picker = resty_chash:new(nodes)
        local key = upstream.key
        return {
            get = function (ctx)
                local id = picker:find(ctx.var[key])
                -- core.log.warn("chash id: ", id, " val: ", servers[id])
                return servers[id]
            end
        }
    end

    return nil, "invalid balancer type: " .. upstream.type, 0
end


local function pick_server(route, ctx)
    core.log.info("route: ", core.json.delay_encode(route, true))
    core.log.info("ctx: ", core.json.delay_encode(ctx, true))
    local upstream = route.value.upstream
    if not upstream then
        return nil, nil, "missing upstream configuration"
    end

    local up_id = upstream.id
    local version

    local key
    if up_id then
        if not upstreams_etcd then
            return nil, nil, "need to create a etcd instance for fetching "
                             .. "upstream information"
        end

        local upstream_obj = upstreams_etcd:get(tostring(up_id))
        if not upstream_obj then
            return nil, nil, "failed to find upstream by id: " .. up_id
        end
        core.log.info("upstream: ", core.json.delay_encode(upstream_obj))

        upstream = upstream_obj.value
        version = upstream_obj.modifiedIndex
        key = upstream.type .. "#upstream_" .. up_id

    else
        version = ctx.conf_version
        key = upstream.type .. "#route_" .. route.value.id
    end

    if upstream.checks and not upstream.checker then
        local checker = healthcheck.new({
            name = "upstream",
            shm_name = "upstream-healthcheck",
            checks = upstream.checks,
        })

        upstream.checker = checker

        -- stop the checker by `gc`
        core.table.setmt__gc(upstream, {__gc = function()
            if worker_exiting() then
                return
            end

            checker:stop()
        end})

        for addr, weight in pairs(upstream.nodes) do
            local ip, port = parse_addr(addr)
            local ok, err = checker:add_target(ip, port, upstream.checks.host)
            if not ok then
                core.log.error("failed to add new health check target: ", addr,
                               " err: ", err)
            end
        end

        core.log.warn("create checks obj for upstream, check")
    end

    if upstream.checks then
        version = version .. "#" .. upstream.checker.status_ver
    end

    local server_picker = lrucache_server_picker(key, version,
                                                 create_server_picker, upstream)
    if not server_picker then
        return nil, nil, "failed to fetch server picker"
    end

    local server, err = server_picker.get(ctx)
    if not server then
        return nil, nil, "failed to find valid upstream server" .. err
    end

    return parse_addr(server)
end
-- for test
_M.pick_server = pick_server


function _M.run(route, ctx)
    local host, port, err = pick_server(route, ctx)
    if err then
        core.log.error("failed to pick server: ", err)
        return core.response.exit(502)
    end

    local ok, err = balancer.set_current_peer(host, port)
    if not ok then
        core.log.error("failed to set server peer: ", err)
        return core.response.exit(502)
    end

    ctx.proxy_passed = true
end


function _M.init_worker()
    local err
    upstreams_etcd, err = core.config.new("/upstreams", {
                                automatic = true,
                                item_schema = core.schema.upstream
                            })
    if not upstreams_etcd then
        error("failed to create etcd instance for fetching upstream: " .. err)
        return
    end
end


return _M
