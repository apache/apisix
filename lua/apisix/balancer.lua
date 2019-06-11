local roundrobin = require("resty.roundrobin")
local resty_chash = require("resty.chash")
local balancer = require("ngx.balancer")
local core = require("apisix.core")
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
local lrucache_get = core.lrucache.new({ttl = 300, count = 256})


local _M = {
    version = 0.1,
    name = module_name,
}


local function create_server_picker(upstream)
    core.log.info("create create_obj, type: ", upstream.type,
                  " nodes: ", core.json.delay_encode(upstream.nodes))

    if upstream.type == "roundrobin" then
        local picker = roundrobin:new(upstream.nodes)
        return {
            get = function ()
                return picker:find()
            end
        }
    end

    if upstream.type == "chash" then
        local str_null = str_char(0)

        local servers, nodes = {}, {}
        for serv, weight in pairs(upstream.nodes) do
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


local function parse_addr(addr)
    local pos = find_str(addr, ":", 1, true)
    if not pos then
        return addr, 80
    end

    local host = sub_str(addr, 1, pos - 1)
    local port = sub_str(addr, pos + 1)
    return host, tonumber(port)
end


local function pick_server(route, ctx)
    core.log.info("route: ", core.json.delay_encode(route, true))
    core.log.info("ctx: ", core.json.delay_encode(ctx, true))
    local upstream = route.value.upstream
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

    local server_picker = lrucache_get(key, version,
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
        error("failed to pick server: " .. err)
    end

    local ok, err = balancer.set_current_peer(host, port)
    if not ok then
        error("failed to set server peer: " .. err)
    end
end


function _M.init_worker()
    local err
    upstreams_etcd, err = core.config.new("/upstreams",
                                          {automatic = true})
    if not upstreams_etcd then
        error("failed to create etcd instance to fetch upstream: " .. err)
        return
    end
end


return _M
