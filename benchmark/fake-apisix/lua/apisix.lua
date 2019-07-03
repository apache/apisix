local balancer = require "ngx.balancer"
local _M = {version = 0.1}

function _M.http_init()
end

function _M.http_init_worker()
end

local function fake_fetch()
    ngx.ctx.ip = "127.0.0.1"
    ngx.ctx.port = 80
end

function _M.http_access_phase()
    local uri = ngx.var.uri
    local host = ngx.var.host
    local method = ngx.req.get_method()
    local remote_addr = ngx.var.remote_addr
    fake_fetch(uri, host, method, remote_addr)
end

function _M.http_header_filter_phase()
    if ngx.ctx then
        -- do something
    end
end

function _M.http_log_phase()
    if ngx.ctx then
        -- do something
    end
end

function _M.http_admin()
end

function _M.http_ssl_phase()
    if ngx.ctx then
        -- do something
    end
end

function _M.http_balancer_phase()
    local ok, err = balancer.set_current_peer(ngx.ctx.ip, ngx.ctx.port)
    if not ok then
        ngx.log(ngx.ERR, "failed to set the current peer: ", err)
        return ngx.exit(500)
    end
end

return _M
