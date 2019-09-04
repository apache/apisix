local healthcheck = require("resty.healthcheck")
local roundrobin  = require("resty.roundrobin")
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
local set_more_tries = balancer.set_more_tries
local get_last_failure = balancer.get_last_failure
local set_timeouts = balancer.set_timeouts


local module_name = "balancer"


local lrucache_server_picker = core.lrucache.new({
    ttl = 300, count = 256
})
local lrucache_checker = core.lrucache.new({
    ttl = 300, count = 256
})


local _M = {
    version = 0.1,
    name = module_name,
}

--[[
-- 根据ip:port转化成 ip,port
 ]]
local function parse_addr(addr)
    local pos = find_str(addr, ":", 1, true)
    if not pos then
        return addr, 80
    end

    local host = sub_str(addr, 1, pos - 1)
    local port = sub_str(addr, pos + 1)
    return host, tonumber(port)
end

--[[
-- 提取健康的上有节点
 ]]
local function fetch_health_nodes(upstream, checker)
    -- 没有设置健康检查，返回所有配置的上游节点
    if not checker then
        return upstream.nodes
    end

    local host = upstream.checks and upstream.checks.host
    local up_nodes = core.table.new(0, #upstream.nodes)

    -- 轮询获取上游主机的状态
    for addr, weight in pairs(upstream.nodes) do
        local ip, port = parse_addr(addr)
        local ok = checker:get_target_status(ip, port, host)
        if ok then
            -- 将权重加入到上线主机列表中心去
            up_nodes[addr] = weight
        end
    end

    --  如果所有节点都不健康，默认所有节点
    if core.table.nkeys(up_nodes) == 0 then
        core.log.warn("all upstream nodes is unhealth, use default")
        up_nodes = upstream.nodes
    end

    return up_nodes
end


local function create_checker(upstream, healthcheck_parent)
    local checker = healthcheck.new({
        name = "upstream#" .. tostring(upstream),
        shm_name = "upstream-healthcheck",
        checks = upstream.checks,
    })

    -- 增加checker 的目的地址
    for addr, weight in pairs(upstream.nodes) do
        local ip, port = parse_addr(addr)
        local ok, err = checker:add_target(ip, port, upstream.checks.host)
        if not ok then
            core.log.error("failed to add new health check target: ", addr,
                            " err: ", err)
        end
    end

    -- 如果upstream是通过upstream_id应用的， parent指向被引用的route
    if upstream.parent then
        core.table.insert(upstream.parent.clean_handlers, function ()
            core.log.info("try to release checker: ", tostring(checker))
            --停止检查器
            checker:stop()
        end)

    else
        core.table.insert(healthcheck_parent.clean_handlers, function ()
            core.log.info("try to release checker: ", tostring(checker))
            --停止检查器
            checker:stop()
        end)
    end

    core.log.info("create new checker: ", tostring(checker))
    return checker
end

--[[
-- 提取健康检查器
 ]]
local function fetch_healthchecker(upstream, healthcheck_parent, version)
    -- 是否配置健康检查的参数
    if not upstream.checks then
        return
    end

    if upstream.checker then
        return
    end

    -- 加入到lru缓存
    local checker = lrucache_checker(upstream, version,
                                     create_checker, upstream,
                                     healthcheck_parent)
    return checker
end

--[[
-- 创建负载分发选择器
 ]]
local function create_server_picker(upstream, checker)
    if upstream.type == "roundrobin" then
        local up_nodes = fetch_health_nodes(upstream, checker)
        core.log.info("upstream nodes: ", core.json.delay_encode(up_nodes))
        --初始化一个RR算法的负载策略
        local picker = roundrobin:new(up_nodes)
        return {
            upstream = upstream,
            get = function ()
                return picker:find()
            end
        }
    end

    if upstream.type == "chash" then
        local up_nodes = fetch_health_nodes(upstream, checker)
        core.log.info("upstream nodes: ", core.json.delay_encode(up_nodes))

        local str_null = str_char(0)

        local servers, nodes = {}, {}
        for serv, weight in pairs(up_nodes) do
            local id = str_gsub(serv, ":", str_null)

            servers[id] = serv
            nodes[id] = weight
        end
        --初始化一个chash 算法的负载策略
        local picker = resty_chash:new(nodes)
        --对这个key进行hash
        local key = upstream.key
        return {
            upstream = upstream,
            get = function (ctx)
                local id = picker:find(ctx.var[key])
                -- core.log.warn("chash id: ", id, " val: ", servers[id])
                return servers[id]
            end
        }
    end

    return nil, "invalid balancer type: " .. upstream.type, 0
end

--[[
--  根据负载策略提取上游主机实例
 ]]
local function pick_server(route, ctx)
    core.log.info("route: ", core.json.delay_encode(route, true))
    core.log.info("ctx: ", core.json.delay_encode(ctx, true))
    local healthcheck_parent = route
    local up_id = route.value.upstream_id
    local upstream = route.value.upstream
    if not up_id and not upstream then
        return nil, nil, "missing upstream configuration"
    end

    local version
    local key

    if up_id then
        if not upstreams_etcd then
            return nil, nil, "need to create a etcd instance for fetching "
                             .. "upstream information"
        end

        -- 根据upstream_id 获取upstream_obj
        local upstream_obj = upstreams_etcd:get(tostring(up_id))
        if not upstream_obj then
            return nil, nil, "failed to find upstream by id: " .. up_id
        end
        core.log.info("upstream: ", core.json.delay_encode(upstream_obj))

        healthcheck_parent = upstream_obj
        -- 对象实例
        upstream = upstream_obj.value
        -- etcd上的配置版本
        version = upstream_obj.modifiedIndex
        -- key
        key = upstream.type .. "#upstream_" .. up_id
    else
        -- 从配置conf_version获取
        version = ctx.conf_version
        -- route
        key = upstream.type .. "#route_" .. route.value.id
    end

    -- 提取健康检查
    local checker = fetch_healthchecker(upstream, healthcheck_parent, version)
    local retries = upstream.retries
    if retries and retries > 0 then
        ctx.balancer_try_count = (ctx.balancer_try_count or 0) + 1
        if checker and ctx.balancer_try_count > 1 then
            local state, code = get_last_failure()
            if state == "failed" then
                if code == 504 then
                    --报告超时
                    checker:report_timeout(ctx.balancer_ip, ctx.balancer_port,
                                           upstream.checks.host)
                else
                    --报告tcp失败
                    checker:report_tcp_failure(ctx.balancer_ip,
                        ctx.balancer_port, upstream.checks.host)
                end

            else
                --报告http状态
                checker:report_http_status(ctx.balancer_ip, ctx.balancer_port,
                                           upstream.checks.host, code)
            end
        end

        if ctx.balancer_try_count == 1 then
            -- 设置更多尝试
            set_more_tries(retries)
        end
    end

    if checker then
        version = version .. "#" .. checker.status_ver
    end

    local server_picker = lrucache_server_picker(key, version,
                            create_server_picker, upstream, checker)
    if not server_picker then
        return nil, nil, "failed to fetch server picker"
    end

    -- 获取到上游服务
    local server, err = server_picker.get(ctx)
    if not server then
        return nil, nil, "failed to find valid upstream server" .. err
    end

    -- 关于转发上游超时的设置
    if upstream.timeout then
        local timeout = upstream.timeout
        local ok, err = set_timeouts(timeout.connect, timeout.send,
                                     timeout.read)
        if not ok then
            core.log.error("could not set upstream timeouts: ", err)
        end
    end

    -- 标记到上下文中去
    local ip, port, err = parse_addr(server)
    ctx.balancer_ip = ip
    ctx.balancer_port = port

    return ip, port, err
end
-- for test
_M.pick_server = pick_server


function _M.run(route, ctx)
    -- 根据策略算法提取上游主机的一个ip、port
    local ip, port, err = pick_server(route, ctx)
    if err then
        core.log.error("failed to pick server: ", err)
        return core.response.exit(502)
    end

    -- 负载均衡器导流
    local ok, err = balancer.set_current_peer(ip, port)
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
