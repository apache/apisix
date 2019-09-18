local require = require
local core  = require("apisix.core")
local error = error
local pairs = pairs


local _M = {version = 0.2}


local function filter(route)
    route.has_domain = false
    if not route.value then
        return
    end

    if not route.value.upstream then
        return
    end

    for addr, _ in pairs(route.value.upstream.nodes or {}) do
        local host = core.utils.parse_addr(addr)
        if not core.utils.parse_ipv4(host) and
           not core.utils.parse_ipv6(host) then
            route.has_domain = true
            break
        end
    end

    core.log.info("filter route: ", core.json.delay_encode(route))
end


function _M.http_init_worker()
    local conf = core.config.local_conf()
    local router_http_name = "r3_uri"
    local router_ssl_name = "r3_sni"

    if conf and conf.apisix and conf.apisix.router then
        router_http_name = conf.apisix.router.http or router_http_name
        router_ssl_name = conf.apisix.router.ssl or router_ssl_name
    end

    local router_http = require("apisix.http.router." .. router_http_name)
    router_http.init_worker(filter)
    _M.router_http = router_http

    local router_ssl = require("apisix.http.router." .. router_ssl_name)
    router_ssl.init_worker()
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
    local router_stream = require("apisix.stream.router.ip_port")
    router_stream.stream_init_worker()
    _M.router_stream = router_stream
end


function _M.http_routes()
    return _M.router_http.routes()
end


return _M
