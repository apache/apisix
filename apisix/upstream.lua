local core = require("apisix.core")
local error = error
local tostring = tostring
local ipairs = ipairs
local pairs = pairs
local upstreams_etcd


local _M = {}


function _M.fetch(route, api_ctx)
    local up_id = route.value.upstream_id
    if up_id then
        if not upstreams_etcd then
            return nil, nil, "need to create a etcd instance for fetching "
                             .. "upstream information"
        end

        local up_obj = upstreams_etcd:get(tostring(up_id))
        if not up_obj then
            return nil, nil, "failed to find upstream by id: " .. up_id
        end
        core.log.info("upstream: ", core.json.delay_encode(up_obj))

        local up_conf = up_obj.dns_value or up_obj.value

        api_ctx.upstream_conf = up_conf
        api_ctx.upstream_key = up_conf.type .. "#upstream_" .. up_id
        api_ctx.upstream_version = up_obj.modifiedIndex
        api_ctx.upstream_healthcheck_parent = up_obj
        return
    end

    local up_conf = (route.dns_value and route.dns_value.upstream)
                    or route.value.upstream
    if not up_conf then
        return core.response.exit(500, "missing upstream configuration")
    end

    api_ctx.upstream_conf = up_conf
    api_ctx.upstream_version = api_ctx.conf_version
    api_ctx.upstream_key = up_conf.type .. "#route_" .. route.value.id
    api_ctx.upstream_healthcheck_parent = route
    return
end


function _M.upstreams()
    if not upstreams_etcd then
        return nil, nil
    end

    return upstreams_etcd.values, upstreams_etcd.conf_version
end


function _M.init_worker()
    local err
    upstreams_etcd, err = core.config.new("/upstreams", {
            automatic = true,
            item_schema = core.schema.upstream,
            filter = function(upstream)
                upstream.has_domain = false
                if not upstream.value or not upstream.value.nodes then
                    return
                end

                local nodes = upstream.value.nodes
                if core.table.isarray(nodes) then
                    for _, node in ipairs(nodes) do
                        local host = node.host
                        if not core.utils.parse_ipv4(host) and
                                not core.utils.parse_ipv6(host) then
                            upstream.has_domain = true
                            break
                        end
                    end
                else
                    local new_nodes = core.table.new(core.table.nkeys(nodes), 0)
                    for addr, weight in pairs(nodes) do
                        local host, port = core.utils.parse_addr(addr)
                        if not core.utils.parse_ipv4(host) and
                                not core.utils.parse_ipv6(host) then
                            upstream.has_domain = true
                        end
                        local node = {
                            host = host,
                            port = port,
                            weight = weight,
                        }
                        core.table.insert(new_nodes, node)
                    end
                    upstream.value.nodes = new_nodes
                end

                core.log.info("filter upstream: ", core.json.delay_encode(upstream))
            end,
        })
    if not upstreams_etcd then
        error("failed to create etcd instance for fetching upstream: " .. err)
        return
    end
end


return _M
