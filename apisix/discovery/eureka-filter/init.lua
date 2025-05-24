local eureka = require("apisix.discovery.eureka")
local core = require("apisix.core")
local log = core.log

local _M = {
    version = 0.1
}

function _M.init_worker()
    eureka.init_worker()
end

function _M.nodes(service_name, discovery_args)
    local nodes = eureka.nodes(service_name)
    if not nodes then
        return nil
    end

    if not discovery_args or not discovery_args.zone then
        return nodes
    end

    local zone = discovery_args.zone
    local filtered_nodes = {}

    for _, node in ipairs(nodes) do
        if node.metadata and node.metadata.zone == zone then
            core.table.insert(filtered_nodes, node)
        end
    end

    if #filtered_nodes == 0 then
        log.warn("no nodes found for service [", service_name, "] in zone [", zone, "]")
        return nodes
    end

    return filtered_nodes
end

function _M.dump_data()
    return eureka.dump_data()
end

return _M
