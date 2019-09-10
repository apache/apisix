-- Copyright (C) Yuansheng Wang

local core      = require("apisix.core")
local ipairs    = ipairs
local error     = error
local ngx_exit  = ngx.exit
local user_routes


local _M = {version = 0.1}


function _M.match(api_ctx)
    local routes = _M.routes()
    if not routes then
        core.log.info("not find any user stream route")
        return ngx_exit(1)
    end

    local remote_addr = api_ctx.var.remote_addr
    -- local server_addr = api_ctx.var.server_addr
    -- local server_port = api_ctx.var.server_port

    -- todo: need a better way
    for _, route in ipairs(routes) do
        if route.remote_addr == remote_addr then
            api_ctx.matched_route = route
            return true
        end
    end

    return ngx_exit(1)
end


function _M.routes()
    if not user_routes then
        return nil, nil
    end

    return user_routes.values, user_routes.conf_version
end


function _M.init_worker()
    local err
    user_routes, err = core.config.new("/stream_routes", {
            automatic = true,
            item_schema = core.schema.route
        })
    if not user_routes then
        error("failed to create etcd instance for fetching /stream_routes : "
              .. err)
    end
end


return _M
