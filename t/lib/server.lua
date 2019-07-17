local _M = {}


function _M.hello()
    ngx.say("hello world")
end


function _M.server_port()
    ngx.print(ngx.var.server_port)
end


function _M.limit_conn()
    ngx.sleep(0.3)
    ngx.say("hello world")
end


function _M.status()
    ngx.say("ok")
end


function _M.go()
    local action = string.sub(ngx.var.uri, 2)
    if not _M[action] then
        return ngx.exit(404)
    end

    return _M[action]()
end


return _M
