--[[
--路由的facecade类、代理类
 ]]
local require = require
local core = require("apisix.core")
local local_conf = core.config.local_conf


local _M = {version = 0.1}


function _M.init_worker()
    local conf = local_conf()
    -- 默认使用 r3 路由引擎
    local router_http_name = "r3_uri"
    local router_ssl_name = "r3_sni"

    -- 读取配置文件，确认使用的路由插件
    if conf and conf.apisix and conf.apisix.router then
        router_http_name = conf.apisix.router.http or router_http_name
        router_ssl_name = conf.apisix.router.ssl or router_ssl_name
    end

    local router_http = require("apisix.http.router." .. router_http_name)
    -- 做相应的work初始化
    router_http.init_worker()
    _M.router_http = router_http

    local router_ssl = require("apisix.http.router." .. router_ssl_name)
    -- 做相应的work初始化
    router_ssl:init_worker()
    _M.router_ssl = router_ssl
end


function _M.http_routes()
    return _M.router_http.routes()
end


return _M
