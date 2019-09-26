--[[
     插件类
--]]
local require = require
local core = require("apisix.core")
local pkg_loaded = package.loaded
local sort_tab = table.sort
local pcall = pcall
local ipairs = ipairs
local pairs = pairs
local type = type
local local_plugins = core.table.new(32, 0)
local local_plugins_hash = core.table.new(0, 32)
local local_conf


local _M = {
    version = 0.2,
    load_times = 0,
    plugins = local_plugins,
    plugins_hash = local_plugins_hash,
}


local function sort_plugin(l, r)
    return l.priority > r.priority
end

--[[
    加载某个插件
    @name 插件名
--]]
local function load_plugin(name)
    local pkg_name = "apisix.plugins." .. name
    pkg_loaded[pkg_name] = nil
    --完成插件的加载
    local ok, plugin = pcall(require, pkg_name)
    if not ok then
        core.log.error("failed to load plugin [", name, "] err: ", plugin)
        return
    end
    --检查插件的 优先级 属性
    if not plugin.priority then
        core.log.error("invalid plugin [", name,
                        "], missing field: priority")
        return
    end

    --检查插件的 版本 属性
    if not plugin.version then
        core.log.error("invalid plugin [", name, "] missing field: version")
        return
    end

    --赋值插件名
    plugin.name = name
    --插入本地插件缓存
    core.table.insert(local_plugins, plugin)

    --完成插件的初始化
    if plugin.init then
        plugin.init()
    end

    return
end

--[[
     初始化配置加载
--]]
local function load()
    core.table.clear(local_plugins)
    core.table.clear(local_plugins_hash)
    --读取本地配置文件
    local_conf = core.config.local_conf(true)
    --本地配置的插件列表
    local plugin_names = local_conf.plugins
    if not plugin_names then
        return nil, "failed to read plugin list form local file"
    end

    --是否启用心跳
    if local_conf.apisix and local_conf.apisix.enable_heartbeat then
        core.table.insert(plugin_names, "heartbeat")
    end

    --已处理对象,避免重复插件的加载
    local processed = {}
    for _, name in ipairs(plugin_names) do
        if processed[name] == nil then
            processed[name] = true
            --对本地的plugin_names列表按插件名进行插件的加载
            load_plugin(name)
        end
    end

    -- 根据优先级别进行排序
    -- sort by plugin's priority
    if #local_plugins > 1 then
        sort_tab(local_plugins, sort_plugin)
    end

    -- 把已经加载的插件缓存存储到 hash 表，便于get获取
    for i, plugin in ipairs(local_plugins) do
        local_plugins_hash[plugin.name] = plugin
        if local_conf and local_conf.apisix
           and local_conf.apisix.enable_debug then
            core.log.warn("loaded plugin and sort by priority:",
                          " ", plugin.priority,
                          " name: ", plugin.name)
        end
    end

    -- 加载次数
    _M.load_times = _M.load_times + 1
    core.log.info("load plugin times: ", _M.load_times)
    return local_plugins
end
_M.load = load


--[[
    为了明确变量的作用域,采用 变量加同名函数，来明确 routes 的作用域。
    有些插件被启用后，是希望拦截特定 uri 对外有输出，这里主要是提取插件里存在api功能的
    如 https://github.com/iresty/apisix/blob/master/lua/apisix/plugins/prometheus.lua#L32
--]]
local fetch_api_routes
do
    local routes = {}
function fetch_api_routes()
    core.table.clear(routes)

    for _, plugin in ipairs(_M.plugins) do
        local api_fun = plugin.api
        if api_fun then
            local api_routes = api_fun()
            core.log.debug("feched api routes: ",
                           core.json.delay_encode(api_routes, true))
            for _, route in ipairs(api_routes) do
                core.table.insert(routes, {
                        method = route.methods,
                        uri = route.uri,
                        handler = function (...)
                            local code, body = route.handler(...)
                            if code or body then
                                core.response.exit(code, body)
                            end
                        end
                    })
            end
        end
    end

    return routes
end

end -- do

--[[
     插件里存在的api路由
--]]
function _M.api_routes()
    return core.lrucache.global("plugin_routes", _M.load_times,
                                fetch_api_routes)
end

--[[
     过滤当前匹配路由的插件
--]]
function _M.filter(user_route, plugins)
    plugins = plugins or core.table.new(#local_plugins * 2, 0)
    -- 获取当前路由配置的插件
    local user_plugin_conf = user_route.value.plugins
    if user_plugin_conf == nil then
        if local_conf and local_conf.apisix.enable_debug then
            core.response.set_header("Apisix-Plugins", "no plugin")
        end
        return plugins
    end
    -- 遍历本地插件缓存
    for _, plugin_obj in ipairs(local_plugins) do
        local name = plugin_obj.name
        -- 通过插件名搜索对应的插件
        local plugin_conf = user_plugin_conf[name]
        -- 如果配置插件是 table 并且启用了
        if type(plugin_conf) == "table" and not plugin_conf.disable then
            --缓存插件的实例对象
            core.table.insert(plugins, plugin_obj)
            --插件的配置信息
            core.table.insert(plugins, plugin_conf)
        end
    end

    -- debug模式，回写匹配的插件信息
    if local_conf.apisix.enable_debug then
        local t = {}
        for i = 1, #plugins, 2 do
            core.table.insert(t, plugins[i].name)
        end
        core.response.set_header("Apisix-Plugins", core.table.concat(t, ", "))
    end

    return plugins
end

--[[
    合并 route 信息配置到 service
    @service_conf
    @route_conf
--]]
function _M.merge_service_route(service_conf, route_conf)
    core.log.info("service conf: ", core.json.delay_encode(service_conf))
    -- core.log.info("route conf  : ", core.json.delay_encode(route_conf))

    -- optimize: use LRU to cache merged result
    local new_service_conf

    local changed = false
    if route_conf.value.plugins then
        -- 从route插件配置中拷贝信息到service配置下
        for name, conf in pairs(route_conf.value.plugins) do
            if not new_service_conf then
                new_service_conf = core.table.deepcopy(service_conf)
            end
            new_service_conf.value.plugins[name] = conf
        end
        changed = true
    end

    local route_upstream = route_conf.value.upstream
    if route_upstream then
        -- 拷贝路由下的 upstream 到 servie 配置下
        if not new_service_conf then
            new_service_conf = core.table.deepcopy(service_conf)
        end
        new_service_conf.value.upstream = route_upstream
        --  如果upstream配置有健康检查，则把路由配置指向到 upstream 的 parent 属性
        if route_upstream.checks then
            route_upstream.parent = route_conf
        end
        changed = true
    end

    if route_conf.value.upstream_id then
        if not new_service_conf then
            new_service_conf = core.table.deepcopy(service_conf)
        end
        -- 拷贝 route_conf 里的 upstream_id 到 service 下
        new_service_conf.value.upstream_id = route_conf.value.upstream_id
    end

    -- core.log.info("merged conf : ", core.json.delay_encode(new_service_conf))
    return new_service_conf or service_conf, changed
end


function _M.init_worker()
    load()
end


function _M.get(name)
    return local_plugins_hash and local_plugins_hash[name]
end


return _M
