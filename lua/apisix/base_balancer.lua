local core = require("apisix.core")
local resty_roundrobin = require("resty.roundrobin")
local balancer = require("ngx.balancer")
local lrucache = require("resty.lrucache")
local ngx = ngx
local ngx_exit = ngx.exit
local ngx_ERROR = ngx.ERROR


local module_name = "balancer"
local cache, err = lrucache.new(500)    -- todo: config in yaml


local _M = {
    version = 0.1,
    name = module_name,
}


local function create_obj(typ, nodes)
    -- core.log.warn("create create_obj, type: ", typ, " nodes: ", core.json.encode(nodes))

    if typ == "roundrobin" then
        local obj = resty_roundrobin:new(nodes)
        return obj
    end

    if typ == "chash" then
        return nil, "not supported balancer type: " .. typ, 0
    end

    return nil, "invalid balancer type: " .. typ, 0
end


function _M.run(route)
    -- core.log.warn("conf: ", core.json.encode(conf), " version: ", version)
    local version = route.modifiedIndex
    local upstream = route.value.upstream

    local key = upstream.type .. "#" .. route.id .. "#" .. version

    local obj, stale_obj = cache:get(key)
    if not obj then
        if stale_obj and stale_obj.conf_version == version then
            obj = stale_obj
        else
            obj, err = create_obj(upstream.type, upstream.nodes)
            if not obj then
                core.log.error("failed to get balancer object: ", err)
                ngx_exit(ngx_ERROR)
                return
            end
            obj.conf_version = version
        end

        -- todo: need a way to clean the old cache
        -- todo: config in yaml
        cache:set(key, obj, 3600)
    end

    local server
    server, err = obj:find()
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


return _M
