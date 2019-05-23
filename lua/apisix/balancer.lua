local core = require("apisix.core")
local roundrobin = require("resty.roundrobin")
local balancer = require("ngx.balancer")
local upstreams_etcd
local ngx = ngx
local ngx_exit = ngx.exit
local ngx_ERROR = ngx.ERROR
local error = error
local module_name = "balancer"


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


function _M.run(route, ctx)
    -- core.log.warn("conf: ", core.json.encode(conf), " version: ", version)
    local upstream = route.value.upstream
    local up_id = upstream.id
    local version

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
        version = upstream_obj.modifiedIndex
        key = upstream.type .. "#upstream_" .. up_id .. "#"
              .. version

    else
        version = ctx.conf_version
        key = upstream.type .. "#route_" .. route.id .. "#" .. version
    end

    local server_piker = core.lrucache.plugin(module_name, key, version,
                            create_server_piker, upstream.type, upstream.nodes)
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
