local json_decode = require("cjson").decode

local _M = {}


function _M.hello()
    ngx.say("hello world")
end

function _M.hello1()
    ngx.say("hello1 world")
end


function _M.server_port()
    ngx.print(ngx.var.server_port)
end


function _M.limit_conn()
    ngx.sleep(0.3)
    ngx.say("hello world")
end

function _M.plugin_proxy_rewrite()
    ngx.say("uri: ", ngx.var.uri)
    ngx.say("host: ", ngx.var.host)
    ngx.say("scheme: ", ngx.var.scheme)
end

function _M.status()
    ngx.say("ok")
end

function _M.sleep1()
    ngx.sleep(1)
    ngx.say("ok")
end

function _M.uri()
    -- ngx.sleep(1)
    ngx.say("uri: ", ngx.var.uri)
    local headers = ngx.req.get_headers()
    for k, v in pairs(headers) do
        ngx.say(k, ": ", v)
    end
end

function _M.old_uri()
    -- ngx.sleep(1)
    ngx.say("uri: ", ngx.var.uri)
    local headers = ngx.req.get_headers()
    for k, v in pairs(headers) do
        ngx.say(k, ": ", v)
    end
end


function _M.opentracing()
    ngx.say("opentracing")
end


function _M.mock_zipkin()
    ngx.req.read_body()
    local data = ngx.req.get_body_data()
    local spans = json_decode(data)
    if #spans < 5 then
        ngx.exit(400)
    end

    for _, span in pairs(spans) do
        if string.sub(span.name, 1, 6) ~= 'apisix' then
            ngx.exit(400)
        end
        if not span.traceId then
            ngx.exit(400)
        end
    end
end


function _M.go()
    local action = string.sub(ngx.var.uri, 2)
    local find = string.find(action, "/", 1, true)
    if find then
        action = string.sub(action, 1, find - 1)
    end

    if not action or not _M[action] then
        return ngx.exit(404)
    end

    return _M[action]()
end


return _M
