local require = require
local core = require("apisix.core")
local local_conf = core.config.local_conf
local error = error


local _M = {version = 0.2}


function _M.http_init_worker()
    local conf = local_conf()
    local router_http_name = "r3_uri"
    local router_ssl_name = "r3_sni"

    if conf and conf.apisix and conf.apisix.router then
        router_http_name = conf.apisix.router.http or router_http_name
        router_ssl_name = conf.apisix.router.ssl or router_ssl_name
    end

    local router_http = require("apisix.http.router." .. router_http_name)
    router_http.init_worker()
    _M.router_http = router_http

    local router_ssl = require("apisix.http.router." .. router_ssl_name)
    router_ssl:init_worker()
    _M.router_ssl = router_ssl

    local global_rules, err = core.config.new("/global_rules", {
            automatic = true,
            item_schema = core.schema.global_rule
        })
    if not global_rules then
        error("failed to create etcd instance for fetching /global_rules : "
              .. err)
    end
    _M.global_rules = global_rules
end


function _M.stream_init_worker()
    local router_stream = require("apisix.stream.router.ip_remote")
    router_stream.init_worker()
    _M.router_stream = router_stream
end


function _M.http_routes()
    return _M.router_http.routes()
end


return _M
