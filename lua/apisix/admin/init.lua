local core = require("apisix.core")
local route = require("resty.r3")
local get_method = ngx.req.get_method
local str_lower = string.lower
local ngx = ngx


local resources = {
    routes    = require("apisix.admin.routes"),
    services  = require("apisix.admin.services"),
    upstreams = require("apisix.admin.upstreams"),
    consumers = require("apisix.admin.consumers"),
    schema    = require("apisix.admin.schema"),
    ssl       = require("apisix.admin.ssl"),
    plugins   = require("apisix.admin.plugins"),
}


local _M = {version = 0.1}
local router


local function run(params)

    local resource = resources[params.res]
    if not resource then
        core.response.exit(404)
    end

    local method = str_lower(get_method())
    if not resource[method] then
        core.response.exit(404)
    end

    ngx.req.read_body()
    local req_body = ngx.req.get_body_data()

    if req_body then
        local data, err = core.json.decode(req_body)
        if not data then
            core.log.error("invalid request body: ", req_body, " err: ", err)
            core.response.exit(401, {error_msg = "invalid request body",
                                     req_body = req_body})
        end

        req_body = data
    end

    local code, data = resource[method](params.id, req_body)
    if code then
        core.response.exit(code, data)
    end
end

local function get_plugins_list()
    local plugins = resources.plugins.get_plugins_list()
    core.response.exit(200, plugins)
end

local uri_route = {
    {
        path = [[/apisix/admin/{res:routes|services|upstreams|consumers|ssl}]],
        handler = run
    },
    {
        path = [[/apisix/admin/{res:routes|services|upstreams|consumers|ssl}]]
                .. [[/{id:[\d\w_]+}]],
        handler = run
    },
    {
        path = [[/apisix/admin/schema/{res:plugins}/{id:[\d\w-]+}]],
        handler = run
    },
    {
        path = [[/apisix/admin/{res:schema}/]]
                .. [[{id:route|service|upstream|consumer|ssl}]],
        handler = run
    },
    {
        path = [[/apisix/admin/plugins/list]],
        handler = get_plugins_list
    },
}

function _M.init_worker()
    local local_conf = core.config.local_conf()
    if not local_conf.apisix or not local_conf.apisix.enable_admin then
        return
    end

    router = route.new(uri_route)

    router:compile()
end


function _M.get()
    return router
end


return _M
