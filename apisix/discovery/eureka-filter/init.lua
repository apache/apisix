local eureka = require("apisix.discovery.eureka")
local core = require("apisix.core")
local log = core.log

local _M = {
    version = 0.1
}

-- 初始化函数，复用 eureka 模块的初始化
function _M.init_worker()
    eureka.init_worker()
end

-- 获取服务节点并进行过滤
function _M.nodes(service_name, discovery_args)
    -- 获取所有节点
    local nodes = eureka.nodes(service_name)
    if not nodes then
        return nil
    end

    -- 如果没有指定区域，返回所有节点
    if not discovery_args or not discovery_args.zone then
        return nodes
    end

    -- 按区域过滤节点
    local zone = discovery_args.zone
    local filtered_nodes = {}

    for _, node in ipairs(nodes) do
        if node.metadata and node.metadata.zone == zone then
            core.table.insert(filtered_nodes, node)
        end
    end

    if #filtered_nodes == 0 then
        log.warn("no nodes found for service [", service_name, "] in zone [", zone, "]")
        return nodes  -- 如果没有找到节点，返回所有节点作为降级策略
    end

    return filtered_nodes
end

-- 复用 eureka 模块的数据导出
function _M.dump_data()
    return eureka.dump_data()
end

return _M
