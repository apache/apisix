local core = require("apisix.core")
local roundrobin = require("resty.roundrobin")
local balancer = require("ngx.balancer")
local lrucache = require("resty.lrucache")
local upstreams_etcd
local ngx = ngx
local ngx_exit = ngx.exit
local ngx_ERROR = ngx.ERROR
local error = error


local module_name = "balancer"
local cache = lrucache.new(500)    -- todo: config in yaml


local _M = {
    version = 0.1,
    name = module_name,
}


local function create_server_piker(typ, nodes)
    -- core.log.info("create create_obj, type: ", typ,
    --               " nodes: ", core.json.encode(nodes))

    if typ == "roundrobin" then
        return roundrobin:new(nodes)
    end

    if typ == "chash" then
        -- todo: support `chash`
        return nil, "not supported balancer type: " .. typ, 0
    end

    return nil, "invalid balancer type: " .. typ, 0
end


function _M.run(route, version)
    -- core.log.warn("conf: ", core.json.encode(conf), " version: ", version)
    local upstream = route.value.upstream
    local up_id = upstream.id

    local key
    if up_id then
        if not upstreams_etcd then
            core.log.warn("need to create a etcd instance for fetching ",
                          "upstream information")
            ngx_exit(ngx_ERROR)
            return
        end

        local upstream_obj = upstreams_etcd:get(up_id)
        if not upstream_obj then
            core.log.warn("failed to find upstream by id: ", up_id)
            ngx_exit(ngx_ERROR)
            return
        end
        -- core.log.info("upstream: ", core.json.encode(upstream_obj))

        upstream = upstream_obj.value
        key = upstream.type .. "#upstream_" .. up_id .. "#"
              .. upstream_obj.modifiedIndex

    else
        key = upstream.type .. "#route_" .. route.id .. "#" .. version
    end

    local server_piker, stale_server_piker = cache:get(key)
    if not server_piker then
        if stale_server_piker and stale_server_piker.conf_version == version then
            server_piker = stale_server_piker

        else
            local err
            server_piker, err = create_server_piker(upstream.type, upstream.nodes)
            if not server_piker then
                core.log.error("failed to get server piker: ", err)
                ngx_exit(ngx_ERROR)
                return
            end
            server_piker.conf_version = version
        end

        -- todo: need a way to clean the old cache
        -- todo: config in yaml
        cache:set(key, server_piker, 3600)
    end

    local server, err = server_piker:find()
    if not server then
        core.log.error("failed to find valid upstream server", err)
        ngx_exit(ngx_ERROR)
        return
    end

    local ok
    ok, err = balancer.set_current_peer(server)
    if not ok then
        core.log.error("failed to set the current peer: ", err)
        ngx_exit(ngx_ERROR)
        return
    end
end


function _M.init_worker()
    local err
    upstreams_etcd, err = core.config.new("/user_upstreams",
                                          {automatic = true})
    if not upstreams_etcd then
        error("failed to create etcd instance to fetch upstream: " .. err)
        return
    end
end


return _M
