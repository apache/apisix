local get_var = require("resty.ngxvar").fetch
local core = require("apisix.core")
local route = require("resty.r3")
local get_method = ngx.req.get_method
local str_lower = string.lower
local ngx = ngx


local resources = {
    routes   = require("apisix.admin.routes"),
    services = require("apisix.admin.services"),
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

    local segments, err = core.utils.split_uri(get_var("uri"))
    if not segments then
        core.log.error("failed to split uri: ", err)
        core.response.exit(500)
    end
    core.log.info("split uri: ", core.json.delay_encode(segments))

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

    local code, data = resource[method](segments, req_body)
    if code then
        core.response.exit(code, data)
    end
end


function _M.init_worker()
    local local_conf = core.config.local_conf()
    if not local_conf.apisix or not local_conf.apisix.enable_admin then
        return
    end

    router = route.new({
        -- todo: support routes|upstreams|service
        {0, [[/apisix/admin/{res:routes|services}]], run},
        {0, [[/apisix/admin/{res:routes|services}/{id:\d+}]], run},
    })

    router:compile()
end


function _M.get()
    return router
end


return _M
